docker run --name pg \
  -e POSTGRES_PASSWORD=secret \
  -p 5432:5432 \
  -d postgres:18