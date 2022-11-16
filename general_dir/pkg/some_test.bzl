script_content = """
#!/bin/bash
mkdir {local_cache_path} &&
cp {input_file} {local_cache_path} &&
{docker_bin_path} load -i {image_tar_file} &&
{docker_bin_path} run -d -i --name {container_name} --mac-address {container_virtual_mac_addr} -v {local_cache_path}:{container_target_actions_folder_path}/ {docker_image_name}:{docker_image_tag} bash &&
{docker_bin_path} exec -w {container_target_actions_folder_path}/ {container_name} {container_exec_command} &&
{docker_bin_path} stop {container_name}
{docker_bin_path} rm {container_name} &&
cp {local_cache_path}/{outfile_name} {outfile_path} &&
rm -rf {local_cache_path}
"""

container_virtual_mac_addr = "12:34:56:78:9a:bc"
container_target_actions_folder_path = "/data"


def _some_test_impl(ctx):

    # Rule's output file
    container_output_file = ctx.actions.declare_file("container_output.txt")

    # A bash script which generates a .txt file
    runfile = ctx.actions.declare_file("container_runfile.bash")
    ctx.actions.write(runfile, "echo \"echo \"Hi My Name Is Oran\" \" >> {outfile_name}".format(outfile_name = container_output_file.basename))

    #########################
    # Docker Configurations #
    #########################

    # Docker image's name
    docker_image_name = ctx.attr.docker_dep.label.workspace_name

    # The docker image's tag is the container_image target's name
    docker_image_tag = ctx.attr.docker_dep.files.to_list()[0].basename.strip("." + ctx.attr.docker_dep.files.to_list()[0].extension)

    # Gets the docker binary path from docker_toolchain
    docker_bin_path = ctx.toolchains["@io_bazel_rules_docker//toolchains/docker:toolchain_type"].info.tool_path

    # The generated container's name (Must be Unique)
    container_name = "-".join([ctx.label.package.replace("/", "_"), ctx.label.name])

    # Local Directory on the host which will function as the work directory of the container
    local_cache_path = "~/" + container_name

    # Execution command on the docker's container
    container_exec_command = "bash {container_target_actions_folder_path}/{runfile_name}".format(
        container_target_actions_folder_path = container_target_actions_folder_path,
        runfile_name = runfile.basename
    )

    # Main action script
    docker_action_runfile = ctx.actions.declare_file("{label_name}_docker_action.bash".format(label_name = ctx.label.name))
    ctx.actions.write(
        docker_action_runfile,
        script_content.format(
            local_cache_path = local_cache_path,
            input_file = runfile.path,
            docker_bin_path = docker_bin_path,
            image_tar_file = ctx.attr.docker_dep.files.to_list()[0].path,
            container_name = container_name,
            container_virtual_mac_addr = container_virtual_mac_addr,
            docker_image_name = docker_image_name,
            docker_image_tag = docker_image_tag,
            container_target_actions_folder_path = container_target_actions_folder_path,
            container_exec_command = container_exec_command,
            outfile_name = container_output_file.basename,
            outfile_path = container_output_file.path,
        ),
        is_executable = True
    )

    ctx.actions.run(
        outputs = [container_output_file],
        inputs = ctx.attr.docker_dep.files.to_list() + [runfile],
        executable = docker_action_runfile,
        progress_message = "Running docker commands inside an bazel's action",

        # The docker toolchain must run on non-sandbox mode (runs the docker binary from the host)
        execution_requirements = {"no-sandbox" : "1"}
    )
    
    return [DefaultInfo(executable = container_output_file)]

some_test = rule(
    implementation = _some_test_impl,
    attrs = {
        "docker_dep" : attr.label(
            allow_files = [".tar"],
            default = "@ubuntu_dockerfile//image:dockerfile_image.tar"
        ),
    },
    toolchains = ["@io_bazel_rules_docker//toolchains/docker:toolchain_type"],
    test = True,
)
