# =============================================================================
#  MULTI-STAGE BUILD
#
#  Stage 1 ("builder") has the whole Go toolchain — compiler, standard library
#  source, module cache. It is ~800 MB and none of it is needed to RUN the app.
#
#  Stage 2 copies out just the compiled binary. Everything else is discarded,
#  because only the final stage becomes the image.
# =============================================================================

# ---------- Stage 1: BUILD ----------
FROM golang:1.22-alpine AS builder

WORKDIR /build

# go.mod first so the dependency layer caches independently of the source
COPY go.mod ./
RUN go mod download

COPY main.go ./

# CGO_ENABLED=0 produces a fully STATIC binary with no libc dependency, which is
# what makes it runnable in an image that contains literally nothing else.
#   -ldflags="-s -w" strips the symbol table and DWARF debug info (~30% smaller).
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/server main.go

# ---------- Stage 2: RUNTIME ----------
# "scratch" is the empty image: zero bytes, no shell, no package manager, no libc.
# The final image is the binary and nothing else.
FROM scratch

LABEL maintainer="Saswata Das <24BCS10248>"
LABEL description="Hello World from Docker multi-stage build"

# Copy ONLY the compiled artefact out of the builder stage
COPY --from=builder /app/server /server

# Run as a non-root UID. There is no /etc/passwd in scratch, so the numeric form
# is required — a named user could not be resolved.
USER 65534

ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["/server"]
