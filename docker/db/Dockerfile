FROM library/postgres
# ADD docker/db/init.sql /docker-entrypoint-initdb.d/
ADD upstream/server/canvas.sql /docker-entrypoint-initdb.d/
ADD docker/db/data.sql /docker-entrypoint-initdb.d/
