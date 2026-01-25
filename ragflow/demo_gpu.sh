# how to
# https://github.com/infiniflow/ragflow?tab=readme-ov-file

git clone https://github.com/infiniflow/ragflow.git
cd ragflow/docker
sed -i '1i DEVICE=gpu' .env
docker compose -f docker-compose.yml up -d
