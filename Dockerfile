# Run with:
#
# docker build --target artifacts --output type=local,dest=. .
#
# Take the artifacts from the /artifacts directory

FROM    rust:1.88 AS dev

RUN     useradd --create-home --shell /bin/bash cloudpub
WORKDIR /home/cloudpub
USER    root

RUN     rustup target add x86_64-unknown-linux-gnu
RUN     rustup target add x86_64-unknown-linux-musl

#       Install aarch64 toolchain
RUN     apt update && \
        apt install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross

#       Install ARM toolchain
RUN     apt install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf libc6-dev-armhf-cross
RUN     apt install -y gcc-arm-linux-gnueabi g++-arm-linux-gnueabi libc6-dev-armel-cross

#       Install x86_64 Windows toolchain
RUN     apt install -y gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64

#       Install MIPS (little-endian) toolchain
RUN     apt install -y gcc-mipsel-linux-gnu g++-mipsel-linux-gnu libc6-dev-mipsel-cross

#       Install additional packages and musl cross-compilation support  
RUN     apt-get update && apt install -y gcc-mipsel-linux-gnu g++-mipsel-linux-gnu libc6-dev-mipsel-cross
RUN     apt install -y gcc-mips-linux-gnu g++-mips-linux-gnu libc6-dev-mips-cross
RUN     apt install -y musl-tools musl-dev
RUN     wget -O - https://musl.cc/mipsel-linux-musl-cross.tgz | tar -xzC /opt/
RUN     wget -O - https://musl.cc/mips-linux-musl-cross.tgz | tar -xzC /opt/
ENV     PATH="/opt/mipsel-linux-musl-cross/bin:/opt/mips-linux-musl-cross/bin:$PATH"

#       Install musl tools for static linking

ENV     HOME="/home/cloudpub"
USER    root

#       Base dependencies
RUN     apt-get update
RUN     apt-get install -y sudo file curl libcap2-bin libxml2 mime-support git-core

#       Support of i686 build
RUN     dpkg --add-architecture i386 && apt-get update

#       Common dependencie
RUN     apt install -y build-essential cmake clang lld

#       Install ARM toolchains
RUN     apt install -y gcc-arm-linux-gnueabi g++-arm-linux-gnueabi
RUN     apt install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
RUN     apt install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
RUN     apt install -y protobuf-compiler

#       Install Windows cross-compilation tools
RUN     apt install -y gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64

#       Install MIPS (little-endian) toolchain
RUN     apt-get update && apt install -y gcc-mipsel-linux-gnu g++-mipsel-linux-gnu libc6-dev-mipsel-cross

#       Install MIPS (big-endian) toolchain
RUN     apt install -y gcc-mips-linux-gnu g++-mips-linux-gnu libc6-dev-mips-cross

#       Install musl tools for static linking
RUN     apt install -y musl-tools

USER    cloudpub:cloudpub

RUN     cargo install cargo-chef

# Add MIPS target using nightly toolchain as it might have more targets
RUN     rustup toolchain install nightly
RUN     rustup +nightly component add rust-src
RUN     rustup +nightly target add mipsel-unknown-linux-musl || true
RUN     rustup +nightly target add mips-unknown-linux-musl || true
RUN     rustup target add arm-unknown-linux-musleabi
RUN     rustup target add armv5te-unknown-linux-musleabi
RUN     rustup target add aarch64-unknown-linux-musl
RUN     rustup target add x86_64-pc-windows-gnu
FROM    dev AS planner
COPY    --chown=cloudpub:cloudpub . $HOME

WORKDIR $HOME
RUN     cargo chef prepare --recipe-path recipe.json

##########################################
FROM    dev AS builder
COPY    --from=planner $HOME/recipe.json $HOME/recipe.json

ENV     CARGO_TARGET_ARM_UNKNOWN_LINUX_GNUEABIHF_LINKER=/usr/bin/arm-linux-gnueabihf-gcc
ENV     CARGO_TARGET_ARM_UNKNOWN_LINUX_MUSLEABI_LINKER=/usr/bin/arm-linux-gnueabi-gcc
ENV     CARGO_TARGET_ARMV5TE_UNKNOWN_LINUX_MUSLEABI_LINKER=/usr/bin/arm-linux-gnueabi-gcc
ENV     CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=/usr/bin/aarch64-linux-gnu-gcc
ENV     CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=/usr/bin/x86_64-w64-mingw32-gcc
# Let Rust handle linking for MIPS musl targets with build-std

WORKDIR $HOME

RUN     cargo chef cook --bin client --profile minimal --target x86_64-unknown-linux-gnu --recipe-path $HOME/recipe.json
RUN     cargo chef cook --bin client --profile minimal --target arm-unknown-linux-musleabi --no-default-features --recipe-path $HOME/recipe.json
RUN     cargo chef cook --bin client --profile minimal --target armv5te-unknown-linux-musleabi --no-default-features --recipe-path $HOME/recipe.json
RUN     cargo chef cook --bin client --profile minimal --target aarch64-unknown-linux-musl --no-default-features --recipe-path $HOME/recipe.json
RUN     cargo chef cook --bin client --profile minimal --target x86_64-pc-windows-gnu --recipe-path $HOME/recipe.json
        # Skip cargo-chef for MIPS targets due to zstd-sys cross-compilation issues

COPY    --chown=cloudpub:cloudpub . $HOME
USER    cloudpub:cloudpub
ENV     PATH="$PATH:$HOME/bin"

# Build client for all targets and create artifacts
RUN     mkdir -p artifacts/win64 && \
        cargo build -p client --target x86_64-pc-windows-gnu --profile minimal && \
        cp target/x86_64-pc-windows-gnu/minimal/client.exe artifacts/win64/clo.exe

RUN     mkdir -p artifacts/x86_64 && \
        cargo build -p client --target x86_64-unknown-linux-gnu --profile minimal && \
        cp target/x86_64-unknown-linux-gnu/minimal/client artifacts/x86_64/clo

RUN     mkdir -p artifacts/aarch64 && \
        cargo build -p client --target aarch64-unknown-linux-musl --profile minimal --no-default-features && \
        cp target/aarch64-unknown-linux-musl/minimal/client artifacts/aarch64/clo

RUN     mkdir -p artifacts/arm && \
        cargo build -p client --target arm-unknown-linux-musleabi --profile minimal --no-default-features && \
        cp target/arm-unknown-linux-musleabi/minimal/client artifacts/arm/clo

RUN     mkdir -p artifacts/armv5te && \
        cargo build -p client --target armv5te-unknown-linux-musleabi --profile minimal --no-default-features && \
        cp target/armv5te-unknown-linux-musleabi/minimal/client artifacts/armv5te/clo

        # Debug musl toolchain structure first
        RUN     find /opt/musl-toolchain -name "*.o" -type f | head -20 && \
                find /opt/musl-toolchain -name "libunwind*" -type f | head -10 && \
                ls -la /opt/musl-toolchain/mips-linux-musl/lib/ || true && \
                ls -la /opt/musl-toolchain/lib/gcc/mips-linux-musl/ || true

        # Install musl-cross from musl.cc (known working MIPS toolchains)
        RUN     cd /tmp && \
                curl -L https://musl.cc/mips-linux-musl-cross.tgz | tar -xz -C /opt && \
                curl -L https://musl.cc/mipsel-linux-musl-cross.tgz | tar -xz -C /opt && \
                ls -la /opt/ && \
                ls -la /opt/mips-linux-musl-cross/bin/ || echo "MIPS BE toolchain not found" && \
                ls -la /opt/mipsel-linux-musl-cross/bin/ || echo "MIPS LE toolchain not found"

                        # Debug the musl toolchain structure and build MIPS target
                        RUN     find /opt/mips-linux-musl-cross -name "crt*.o" -type f | head -10 && \
                                find /opt/mips-linux-musl-cross -name "libunwind*" -type f | head -5 && \
                                find /opt/mips-linux-musl-cross -type d -name "lib*" | head -5
                        
                        # Create comprehensive stub libunwind for MIPS targets - this resolves the missing libunwind dependency
                        RUN     cat > /tmp/stub_unwind.c << 'EOF'
void _Unwind_Resume(void) {}
void _Unwind_DeleteException(void) {}
unsigned long _Unwind_GetLanguageSpecificData(void) { return 0; }
unsigned long _Unwind_GetRegionStart(void) { return 0; }
unsigned long _Unwind_GetTextRelBase(void) { return 0; }
unsigned long _Unwind_GetDataRelBase(void) { return 0; }
void _Unwind_SetGR(void) {}
void _Unwind_SetIP(void) {}
unsigned long _Unwind_GetGR(void) { return 0; }
unsigned long _Unwind_GetIP(void) { return 0; }
unsigned long _Unwind_GetCFA(void) { return 0; }
void* _Unwind_FindEnclosingFunction(void* pc) { return 0; }
int _Unwind_Backtrace(void* callback, void* ref) { return 0; }
int _Unwind_GetIPInfo(void* context, int* flag) { if (flag) *flag = 0; return 0; }
void _Unwind_RaiseException(void) {}
void _Unwind_ForcedUnwind(void) {}
EOF
                        RUN     /opt/mips-linux-musl-cross/bin/mips-linux-musl-gcc -c /tmp/stub_unwind.c -o /tmp/stub_unwind_mips.o && \
                                /opt/mips-linux-musl-cross/bin/mips-linux-musl-ar rcs /opt/mips-linux-musl-cross/mips-linux-musl/lib/libunwind.a /tmp/stub_unwind_mips.o && \
                                /opt/mips-linux-musl-cross/bin/mips-linux-musl-gcc -c /tmp/stub_unwind.c -o /tmp/stub_unwind_mips_gcc.o && \
                                /opt/mips-linux-musl-cross/bin/mips-linux-musl-ar rcs /opt/mips-linux-musl-cross/lib/gcc/mips-linux-musl/11.2.1/libunwind.a /tmp/stub_unwind_mips_gcc.o && \
                                /opt/mipsel-linux-musl-cross/bin/mipsel-linux-musl-gcc -c /tmp/stub_unwind.c -o /tmp/stub_unwind_mipsel.o && \
                                /opt/mipsel-linux-musl-cross/bin/mipsel-linux-musl-ar rcs /opt/mipsel-linux-musl-cross/mipsel-linux-musl/lib/libunwind.a /tmp/stub_unwind_mipsel.o && \
                                /opt/mipsel-linux-musl-cross/bin/mipsel-linux-musl-gcc -c /tmp/stub_unwind.c -o /tmp/stub_unwind_mipsel_gcc.o && \
                                /opt/mipsel-linux-musl-cross/bin/mipsel-linux-musl-ar rcs /opt/mipsel-linux-musl-cross/lib/gcc/mipsel-linux-musl/11.2.1/libunwind.a /tmp/stub_unwind_mipsel_gcc.o

                        # Build MIPS (big-endian) target with musl.cc cross-compiler - fully static
                        RUN     mkdir -p artifacts/mips && \
                                env LIBZSTD_NO_PKG_CONFIG=1 \
                                    CC=/opt/mips-linux-musl-cross/bin/mips-linux-musl-gcc \
                                    CXX=/opt/mips-linux-musl-cross/bin/mips-linux-musl-g++ \
                                    AR=/opt/mips-linux-musl-cross/bin/mips-linux-musl-ar \
                                    CARGO_TARGET_MIPS_UNKNOWN_LINUX_MUSL_LINKER=/opt/mips-linux-musl-cross/bin/mips-linux-musl-gcc \
                                    RUSTFLAGS="-C target-feature=+crt-static -C link-arg=-static -C panic=abort -C link-arg=-Wl,-no-eh-frame-hdr -C link-arg=-Wl,--as-needed -C link-arg=-Wl,--allow-multiple-definition -L/opt/mips-linux-musl-cross/mips-linux-musl/lib -L/opt/mips-linux-musl-cross/lib/gcc/mips-linux-musl/11.2.1" \
                                    rustup run nightly cargo build \
                                    -Zbuild-std=std,panic_abort \
                                    -p client \
                                    --target mips-unknown-linux-musl \
                                    --profile minimal \
                                    --no-default-features && \
                                cp target/mips-unknown-linux-musl/minimal/client artifacts/mips/clo && \
                                file artifacts/mips/clo && \
                                /opt/mips-linux-musl-cross/bin/mips-linux-musl-readelf -d artifacts/mips/clo | head -20                        # Build MIPSEL (little-endian) target with musl.cc cross-compiler - fully static
                        RUN     mkdir -p artifacts/mipsel && \
                                env LIBZSTD_NO_PKG_CONFIG=1 \
                                    CC=/opt/mipsel-linux-musl-cross/bin/mipsel-linux-musl-gcc \
                                    CXX=/opt/mipsel-linux-musl-cross/bin/mipsel-linux-musl-g++ \
                                    AR=/opt/mipsel-linux-musl-cross/bin/mipsel-linux-musl-ar \
                                    CARGO_TARGET_MIPSEL_UNKNOWN_LINUX_MUSL_LINKER=/opt/mipsel-linux-musl-cross/bin/mipsel-linux-musl-gcc \
                                    RUSTFLAGS="-C target-feature=+crt-static -C link-arg=-static -C panic=abort -C link-arg=-Wl,-no-eh-frame-hdr -C link-arg=-Wl,--as-needed -C link-arg=-Wl,--allow-multiple-definition -L/opt/mipsel-linux-musl-cross/mipsel-linux-musl/lib -L/opt/mipsel-linux-musl-cross/lib/gcc/mipsel-linux-musl/11.2.1" \
                                    rustup run nightly cargo build \
                                    -Zbuild-std=std,panic_abort \
                                    -p client \
                                    --target mipsel-unknown-linux-musl \
                                    --profile minimal \
                                    --no-default-features && \
                                cp target/mipsel-unknown-linux-musl/minimal/client artifacts/mipsel/clo && \
                                file artifacts/mipsel/clo && \
                                /opt/mipsel-linux-musl-cross/bin/mipsel-linux-musl-readelf -d artifacts/mipsel/clo | head -20

FROM scratch AS artifacts
COPY --from=builder /home/cloudpub/artifacts /artifacts