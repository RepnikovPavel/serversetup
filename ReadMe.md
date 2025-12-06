```sh
bash install_system_deps.sh
bash install_docker.sh
bash install_docker_nvtk.sh
```

```sh
bash docker/build_cu130.sh
bash docker/run_cu130.sh ./
python3 docker/torch_check.py
```
