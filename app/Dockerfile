FROM golang:1.22-alpine AS builder
WORKDIR /build
COPY go.mod .
COPY main.go .
RUN go build -o server .

FROM alpine:3.19
RUN addgroup -S app && adduser -S -G app app
USER app
WORKDIR /app
COPY --from=builder /build/server .
EXPOSE 8080
CMD ["./server"]
