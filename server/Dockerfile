# ---- 构建阶段 ----
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY . .
# 首次构建在容器内自动拉取依赖并生成 go.sum
ENV GOFLAGS=-mod=mod
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/xdf-api .

# ---- 运行阶段 ----
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
ENV TZ=Asia/Shanghai \
    PORT=8080 \
    DATA_DIR=/data
WORKDIR /app
COPY --from=build /out/xdf-api .
EXPOSE 8080
VOLUME /data
CMD ["./xdf-api"]
