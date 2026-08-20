#!/usr/bin/env python3
"""Бенчмарк стоимости переключения KV-кэша между двумя пользователями.

Сценарий: два пользователя (два API-ключа) по очереди ведут диалог с моделью.
Сервер держит один слот (--parallel 1) с полным контекстом, поэтому каждое
чередование = передача KV от одного юзера другому. Механизм зависит от модели:
чисто-attention — дисковые снапшоты kvu-*.bin (модуль kv_sessions форка,
--slot-save-path); гибридные/recurrent (qwen35) — in-memory prompt cache
llama-server (--cache-ram), т.к. после disk restore llama.cpp всё равно делает
полный re-prefill (ggml-org/llama.cpp#25913).

Измеряем end-to-end на стороне клиента:
  - cold prefill   — первый запрос юзера с длинным документом (~S токенов);
  - warm turn      — следующий запрос того же юзера без смены слота (baseline);
  - switch turn    — запрос ДРУГОГО юзера = save + restore + досчёт хвоста;
  - overhead       = switch - warm  ≈ чистое время свопа;
  - размер снапшотов на диске (сколько и куда сбрасывается).

Запуск на сервере (или по сети, но лучше на сервере — без сетевого шума):

  KEY_A=sk-unsloth-... KEY_B=sk-unsloth-... python3 tests/bench_kv_switch.py

Переменные:
  SERVER      default http://127.0.0.1:48218
  MODEL       default unsloth/Qwen3.8-27B-GGUF
  SIZES       целевые размеры контекста в токенах, default "4096,16384,65536"
  ITERS       число переключений в каждую сторону на размер, default 3
  CONTAINER   имя docker-контейнера для stat снапшотов, default unsloth-studio-cu128
              (пустое значение — не лезть в docker, печатать только ожидаемые пути)

Только stdlib. Ничего не меняет на сервере, кроме содержимого KV-снапшотов
двух указанных ключей.
"""

import hashlib
import json
import os
import random
import subprocess
import sys
import time
import urllib.request

SERVER = os.environ.get("SERVER", "http://127.0.0.1:48218").rstrip("/")
MODEL = os.environ.get("MODEL", "unsloth/Qwen3.8-27B-GGUF")
KEY_A = os.environ.get("KEY_A", "")
KEY_B = os.environ.get("KEY_B", "")
SIZES = [int(s) for s in os.environ.get("SIZES", "4096,16384,65536").split(",") if s.strip()]
ITERS = int(os.environ.get("ITERS", "3"))
CONTAINER = os.environ.get("CONTAINER", "unsloth-studio-cu128")
SLOT_DIR = "/data/studio/cache/llama-slots"

VOCAB = (
    "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima "
    "mike november oscar papa quebec romeo sierra tango uniform victor whiskey "
    "xray yankee zulu server cache token memory kernel driver socket buffer"
).split()


def make_doc(target_tokens: int, salt: str) -> str:
    """Псевдослучайный текст ~target_tokens (точный размер возьмём из usage)."""
    rng = random.Random(salt)
    words = []
    # грубая оценка: ~1.35 токена на слово с пробелом для такого словаря
    for _ in range(int(target_tokens / 1.3)):
        words.append(rng.choice(VOCAB) + str(rng.randrange(1000)))
    return f"Document {salt}: " + " ".join(words)


def chat(key: str, messages, max_tokens: int = 1) -> dict:
    body = json.dumps({
        "model": MODEL,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 0,
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode()
    req = urllib.request.Request(
        f"{SERVER}/v1/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=1200) as resp:
        data = json.load(resp)
    dt = time.monotonic() - t0
    usage = data.get("usage") or {}
    return {
        "dt": dt,
        "prompt_tokens": usage.get("prompt_tokens", 0),
        "completion_tokens": usage.get("completion_tokens", 0),
    }


def snapshot_files() -> list:
    """[(filename, bytes)] из slot-save-path через docker exec; [] если недоступно."""
    if not CONTAINER:
        return []
    try:
        out = subprocess.run(
            ["docker", "exec", CONTAINER, "sh", "-c",
             f"ls -l {SLOT_DIR}/kvu-*.bin 2>/dev/null"],
            capture_output=True, text=True, timeout=30,
        ).stdout
    except Exception:
        return []
    res = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 9:
            try:
                res.append((parts[-1], int(parts[4])))
            except ValueError:
                pass
    return res


def expected_snapshot_name(key: str) -> str:
    digest = hashlib.sha256(f"{key}|{MODEL}".encode()).hexdigest()
    return f"kvu-{digest[:24]}.bin"


def fmt(t: float) -> str:
    return f"{t:7.2f}s"


def fmt_mb(n: int) -> str:
    return f"{n / 1e6:8.1f} MB"


def main() -> int:
    if not KEY_A or not KEY_B:
        sys.exit("нужны KEY_A и KEY_B (два разных API-ключа = два пользователя)")

    print(f"server={SERVER} model={MODEL} iters={ITERS} sizes={SIZES}")
    name_a, name_b = expected_snapshot_name(KEY_A), expected_snapshot_name(KEY_B)
    print(f"снапшот юзера A: {SLOT_DIR}/{name_a}")
    print(f"снапшот юзера B: {SLOT_DIR}/{name_b}")
    print()

    grand = []
    for target in SIZES:
        nonce = f"{int(time.time())}"
        msgs_a = [{"role": "user", "content": make_doc(target, f"A-{nonce}")}]
        msgs_b = [{"role": "user", "content": make_doc(target, f"B-{nonce}")}]

        # 1. холодный prefill A, затем тёплый ход A (baseline без свопа)
        r = chat(KEY_A, msgs_a)
        cold_a, ptok_a = r["dt"], r["prompt_tokens"]
        msgs_a.append({"role": "user", "content": "ok"})
        r = chat(KEY_A, msgs_a)
        warm_a = [r["dt"]]

        # 2. холодный prefill B (включает первый save A, restore B — промах)
        r = chat(KEY_B, msgs_b)
        cold_b, ptok_b = r["dt"], r["prompt_tokens"]
        msgs_b.append({"role": "user", "content": "ok"})
        r = chat(KEY_B, msgs_b)
        warm_b = [r["dt"]]

        # 3. челночные переключения: каждый ход = save одного + restore другого
        sw_a, sw_b = [], []
        for i in range(ITERS):
            msgs_a.append({"role": "user", "content": f"continue {i}"})
            sw_a.append(chat(KEY_A, msgs_a)["dt"])
            msgs_b.append({"role": "user", "content": f"continue {i}"})
            sw_b.append(chat(KEY_B, msgs_b)["dt"])
            # тёплые ходы рядом для честного baseline на этом размере
            if i == 0:
                warm_a.append(chat(KEY_A, msgs_a)["dt"])
                warm_b.append(chat(KEY_B, msgs_b)["dt"])

        warm = (sum(warm_a) + sum(warm_b)) / (len(warm_a) + len(warm_b))
        switches = sw_a + sw_b
        sw_avg = sum(switches) / len(switches)
        ptok = max(ptok_a, ptok_b)
        overhead = sw_avg - warm

        files = dict(snapshot_files())
        size_a, size_b = files.get(f"{SLOT_DIR}/{name_a}", 0), files.get(f"{SLOT_DIR}/{name_b}", 0)

        print(f"=== контекст ~{ptok} токенов (A={ptok_a}, B={ptok_b}) ===")
        print(f"  cold prefill A : {fmt(cold_a)}  ({ptok_a / cold_a:,.0f} t/s)")
        print(f"  cold prefill B : {fmt(cold_b)}  ({ptok_b / cold_b:,.0f} t/s)")
        print(f"  warm turn (avg): {fmt(warm)}   baseline: тот же юзер, без свопа")
        print(f"  switch A<-B    : {[f'{t:.2f}' for t in sw_a]}")
        print(f"  switch B<-A    : {[f'{t:.2f}' for t in sw_b]}")
        print(f"  switch avg     : {fmt(sw_avg)}  ->  overhead свопа ~{fmt(overhead)}")
        if size_a or size_b:
            bpt = (size_a + size_b) / 2 / max(ptok, 1)
            print(f"  снапшот A: {fmt_mb(size_a)}   снапшот B: {fmt_mb(size_b)}"
                  f"   (~{bpt:,.0f} B/токен)")
        print()
        grand.append((ptok, warm, sw_avg, overhead, size_a, size_b))

    print("=== сводка ===")
    print(f"{'ctx tok':>9} {'warm':>8} {'switch':>8} {'overhead':>9} {'snap A':>10} {'snap B':>10}")
    for ptok, warm, sw, ov, sa, sb in grand:
        print(f"{ptok:>9} {fmt(warm)} {fmt(sw)} {fmt(ov)} {fmt_mb(sa)} {fmt_mb(sb)}")
    print()
    print(f"куда сбрасывается: {SLOT_DIR}/kvu-<sha256(api_key|model)[:24]>.bin"
          f" внутри контейнера {CONTAINER or '?'}")
    print("(на хосте это $UNSLOTH_HOST_DIR/studio/cache/llama-slots, TTL 3 суток)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
