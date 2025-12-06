import torch
import numpy as np

print(f'torch cuda available {torch.cuda.is_available()}')

def get_vram(gpu_index):
    free = torch.cuda.mem_get_info(gpu_index)[0] / 1024 ** 3
    total = torch.cuda.mem_get_info(gpu_index)[1] / 1024 ** 3
    total_cubes = 24
    free_cubes = int(total_cubes * free / total)
    return f'VRAM: {total - free:.2f}/{total:.2f}GB\t VRAM:[' + (
            total_cubes - free_cubes) * '▮' + free_cubes * '▯' + ']'

def test_dtype_basic(dtype_name, dtype_attr, device):
    try:
        if 'int' in dtype_name:
            data = [1, 2, 3, 4]
        else:
            data = [0.1, 0.5, 1.0, 2.0]
            
        x = torch.tensor(data, dtype=dtype_attr, device=device)
        y = x + 1
        return '✅'
    except Exception as e:
        return f'❌ ({str(e)[:25]}...)'

def test_dtype_fp(dtype_name, dtype_attr, device):
    """Тест FP4/FP8: только проверка создания и хранения"""
    try:
        x = torch.tensor([0.1, 0.5, 1.0], dtype=torch.float32, device=device)
        x_cast = x.to(dtype=dtype_attr)
        return '✅ (cast only)'
    except Exception as e:
        return f'❌ ({str(e)[:25]}...)'

def test_all_types():
    basic_types = [
        ('float16', torch.float16),
        ('float32', torch.float32),
        ('float64', torch.float64),
        ('bfloat16', torch.bfloat16),
        ('int8', torch.int8),
        ('int16', torch.int16),
        ('int32', torch.int32),
        ('int64', torch.int64),
        ('uint8', torch.uint8),
    ]
    
    fp_types = [
        'float4_e2m1fn_x2',
        'float8_e4m3fn',
        'float8_e4m3fnuz',
        'float8_e5m2',
        'float8_e5m2fnuz',
        'float8_e8m0fnu'
    ]
    
    results = {'cpu': {}, 'gpu': {}}
    
    print("Testing basic types...")
    for name, dtype in basic_types:
        results['cpu'][name] = test_dtype_basic(name, dtype, 'cpu')
        if torch.cuda.is_available():
            results['gpu'][name] = test_dtype_basic(name, dtype, 'cuda')
    
    print("Testing FP4/FP8 types...")
    for dtype_name in fp_types:
        if hasattr(torch, dtype_name):
            dtype_attr = getattr(torch, dtype_name)
            results['cpu'][dtype_name] = test_dtype_fp(dtype_name, dtype_attr, 'cpu')
            if torch.cuda.is_available():
                results['gpu'][dtype_name] = test_dtype_fp(dtype_name, dtype_attr, 'cuda')
        else:
            results['cpu'][dtype_name] = '❌ (missing)'
            results['gpu'][dtype_name] = '❌ (missing)'
    
    return results

print(f'num gpu detected: {torch.cuda.device_count()}')
if torch.cuda.device_count() > 0:
    print('gpu list:')
    for i in range(torch.cuda.device_count()):
        print(torch.cuda.get_device_name(i))

    for i in range(torch.cuda.device_count()):
        print(get_vram(i))

print('\n=== FULL TYPE SUPPORT TEST ===')
all_results = test_all_types()

print('\nAll types support:')
print('  Type                  | CPU            | GPU')
print('  ---------------------|---------------|---------------')
for dtype_name in sorted(all_results['cpu']):
    cpu_status = all_results['cpu'][dtype_name]
    gpu_status = all_results['gpu'][dtype_name] if torch.cuda.is_available() else 'N/A'
    print(f'  {dtype_name:20} | {cpu_status:13} | {gpu_status:13}')