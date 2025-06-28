FROM golang:1.22-alpine as builder
WORKDIR /app
COPY . .
RUN go build -o user-service

FROM alpine:3.20
WORKDIR /app
COPY --from=builder /app/user-service .
USER nobody
CMD ["./user-service"]
