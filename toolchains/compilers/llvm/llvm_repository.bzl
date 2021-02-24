load("//toolchains/compilers/llvm/impl:llvm_versions.bzl", "TOOLCHAIN_VERSIONS", "get_platform_specific_config")
load("//toolchains/tools/include_tools:include_tools.bzl", "include_tools")

def _llvm_repository_impl(repository_ctx):
    version = repository_ctx.attr.version
    if "windows" not in repository_ctx.os.name:
        remote_toolchain_info = get_platform_specific_config(version, repository_ctx.os.name)
        if repository_ctx.attr.sysroot:
            sysroot_marker = repository_ctx.path(repository_ctx.attr.sysroot)

        repository_ctx.download_and_extract(
            url = remote_toolchain_info["remote_compiler"]["url"],
            sha256 = remote_toolchain_info["remote_compiler"]["sha256"],
            stripPrefix = remote_toolchain_info["remote_compiler"]["strip_prefix"],
        )
    else:
        repository_ctx.download(
            url = "https://github.com/llvm/llvm-project/releases/download/llvmorg-11.1.0/LLVM-11.0.1-win64.exe",
            output = "clang_installer.exe",
        )
        installer_path = repository_ctx.path("clang_installer.exe").realpath
        out = repository_ctx.execute(["powershell", "-c", "'clang_installer.exe \\S \\D=$(pwd)'"])
        print("clang_installer_stdout", out.stdout)
        print("clang_installer_stderr", out.stderr)
    sysroot_args = []
    sysroot_path = ""
    if repository_ctx.attr.sysroot != None:
        sysroot = repository_ctx.attr.sysroot
        sysroot_path = str(sysroot_marker.dirname) + "/root/" + sysroot.package
        sysroot_args = ["--sysroot", sysroot_path]
    response = repository_ctx.execute(include_tools.ShellCommand(
        "bin/clang++",
        sysroot_args,
    ))
    include_paths = include_tools.ProccessResponse(response.stderr)
    include_flags = ["-isystem" + path for path in include_paths]
    include_bazel_template_input = include_tools.CommandLineToTemplateString(include_flags)
    include_paths_template_input = include_tools.CommandLineToTemplateString(include_paths)
    repository_ctx.file(
        "defs.bzl",
        """
SYSTEM_INCLUDE_COMMAND_LINE = {}
SYSTEM_INCLUDE_PATHS= {}
SYSTEM_SYSROOT = "{}"
""".format(include_bazel_template_input, include_paths_template_input, sysroot_path),
    )

    repository_ctx.file(
        "BUILD",
        """
filegroup(
    name = "all",
    srcs = glob(["**/*"],exclude=["**/*.html","**/*.pdf"]),
    visibility = ['//visibility:public'],
)
exports_files(
    glob(["bin/**"])
)
""",
    )

llvm_repository = repository_rule(
    _llvm_repository_impl,
    attrs = {
        "version": attr.string(
            default = "11",
            doc = "LLVM version, version 11 currently only version supported",
            values = TOOLCHAIN_VERSIONS.keys(),
        ),
        "sysroot": attr.label(
            doc = "The sysroot that clang should use to build source",
        ),
    },
)

def llvm_compiler(name = "com_llvm_compiler", sysroot = ""):
    llvm_repository(
        name = name,
        sysroot = sysroot,
    )
