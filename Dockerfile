FROM mcr.microsoft.com/azure-cli AS base

WORKDIR /app

COPY az_cli.sh .

# Creates a non-root user with an explicit UID and adds permission to access the /app folder
# RUN adduser -u 5678 --disabled-password --gecos "" appuser && chown -R appuser /app

# USER appuser

RUN chmod 777 az_cli.sh

CMD [ "./az_cli.sh" ]

