### Create password for MySQL root user
printf "your-mysql-root-password" > mysql_root_password.txt

### Create password for pycells user
sed -i "s/'password'/'your-password'/g" init.sql

### Build and run
docker compose up -d --build