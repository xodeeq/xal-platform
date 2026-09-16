# Multi-stage build for <SERVICE>.
#
# One image, two subcommands (`serve` and `migrate`) — so the release-step migration artifact
# and the runtime are the same bytes, and "the migration that ran" is never a different build
# from "the code that is running".
#
# CGO_ENABLED=0 and a distroless static base: no libc, no shell, no package manager in the
# runtime image, which is both the minimal-image convention and the reason the artifact has
# no dependency on the host it lands on. That portability is deliberate — the hosting
# question is open, and a static binary keeps the switching cost at zero.

FROM golang:1.25 AS build
WORKDIR /src

# Copy the module files first so `go mod download` is cached independently of source edits.
COPY go.mod go.sum* ./
RUN go mod download

COPY . .

# -trimpath so the binary does not embed build-machine paths (reproducibility, and it keeps
# a local path out of a stack trace in production).
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/<SERVICE> ./cmd/<SERVICE>

# `nonroot` rather than `latest`: the runtime convention is a non-root user, and a base that
# defaults to root makes that one forgotten line away from being untrue.
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /
COPY --from=build /out/<SERVICE> /<SERVICE>
USER nonroot:nonroot

# Config comes from the environment; the port is configurable (container-interface
# convention). EXPOSE is documentation — it binds nothing.
EXPOSE 8080

ENTRYPOINT ["/<SERVICE>"]
CMD ["serve"]
