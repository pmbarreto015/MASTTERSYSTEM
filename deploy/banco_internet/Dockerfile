# syntax=docker/dockerfile:1
# Pode fixar a versão com --build-arg DART_IMAGE=dart:3.11.5-sdk.
ARG DART_IMAGE=dart:stable
FROM ${DART_IMAGE} AS build
WORKDIR /app

COPY source/pubspec.* ./
RUN dart pub get
COPY source/bin/ ./bin/
COPY source/lib/ ./lib/
RUN dart build cli --target=bin/servidor_banco.dart --output=output

FROM scratch AS runtime
# Usa o runtime da mesma imagem que compilou o executável.
COPY --from=build /runtime/ /
# bin/ e lib/ precisam permanecer juntos para carregar o SQLite nativo.
COPY --from=build /app/output/bundle/ /app/
WORKDIR /app
EXPOSE 8080
ENTRYPOINT ["/app/bin/servidor_banco"]
