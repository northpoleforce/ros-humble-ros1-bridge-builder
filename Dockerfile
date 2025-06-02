###########################
# 1.) Bring system up to the latest ROS desktop configuration
###########################

FROM osrf/ros:humble-desktop-full-jammy

# Make sure bash catches errors (no need to chain commands with &&, use ; instead)
SHELL ["/bin/bash", "-o", "pipefail", "-o", "errexit", "-c"]

###########################
# 2.) Temporarily remove ROS2 apt repository
###########################

RUN rm /etc/apt/sources.list.d/ros2-latest.list; \
    apt-get update

###########################
# 3.) comment out the catkin conflict
###########################
RUN sed  -i -e 's|^Conflicts: catkin|#Conflicts: catkin|' /var/lib/dpkg/status && \
    apt-get install -f

###########################
# 4.) force install these packages
# 5.) Install the latest ROS1 desktop configuration
# see https://packages.ubuntu.com/jammy/ros-desktop-dev
# note: ros-desktop-dev automatically includes tf tf2
###########################
RUN apt-get download python3-catkin-pkg; \
    apt-get download python3-rospkg; \
    apt-get download python3-rosdistro; \
    dpkg --force-overwrite -i python3-catkin-pkg*.deb; \
    dpkg --force-overwrite -i python3-rospkg*.deb; \
    dpkg --force-overwrite -i python3-rosdistro*.deb; \
    apt-get install -f; \
    \
    apt-get -y install ros-desktop-dev

# fix ARM64 pkgconfig path issue -- Fix provided by ambrosekwok
RUN if [[ $(uname -m) = "arm64" || $(uname -m) = "aarch64" ]]; then                     \
      cp /usr/lib/x86_64-linux-gnu/pkgconfig/* /usr/lib/aarch64-linux-gnu/pkgconfig/;   \
    fi

###########################
# 6.) Restore the ROS2 apt repos and set compilation options.
#   For example, to include ROS tutorial message types, pass
#   "--build-arg ADD_ros_tutorials=1" to the docker build command.
###########################
RUN apt-get -y install curl gnupg; \
	curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg; \
	sh -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] https://mirrors.huaweicloud.com/ros2/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros2-latest.list'; \
	apt-get -y update

# for ros-humble-example-interfaces:
ARG ADD_ros_tutorials=1
# for ros-humble-grid-map:
ARG ADD_grid_map=0
# for a custom message example
ARG ADD_example_custom_msgs=0
# for octomap
ARG ADD_octomap_msgs=0

# sanity check:
RUN echo "ADD_ros_tutorials         = '$ADD_ros_tutorials'"; \
echo "ADD_grid_map              = '$ADD_grid_map'"; \
echo "ADD_example_custom_msgs   = '$ADD_example_custom_msgs'"; \
echo "ADD_octomap_msgs          = '$ADD_octomap_msgs'";

###########################
# 6.1) Add ROS1 ros_tutorials messages and services
# eg., See AddTwoInts server and client tutorial
###########################
RUN if [[ "$ADD_ros_tutorials" = "1" ]]; then                                           \
      git clone -b noetic-devel --depth=1 https://github.com/ros/ros_tutorials.git;     \
      cd ros_tutorials;                                                                 \
      unset ROS_DISTRO;                                                                 \
      time colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release;                        \
    fi

###########################
# 6.2 Add ROS1 grid-map messages
###########################
# navigation stuff (just need costmap_2d?)
RUN if [[ "$ADD_grid_map" = "1" ]]; then                                                        \
      apt-get -y install libsdl1.2-dev libsdl-image1.2-dev;                                     \
      git clone -b noetic-devel --depth=1 https://github.com/ros-planning/navigation.git;       \
      cd navigation;                                                                            \
      unset ROS_DISTRO;                                                                         \
      time colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release                                 \
        --packages-select map_server voxel_grid costmap_2d;                                     \
    fi

# filter stuff
RUN if [[ "$ADD_grid_map" = "1" ]]; then                                        \
      git clone -b noetic-devel --depth=1 https://github.com/ros/filters.git;   \
      cd filters;                                                               \
      unset ROS_DISTRO;                                                         \
      time colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release;                \
    fi

# finally grid-amp (only select a subset for now)
RUN if [[ "$ADD_grid_map" = "1" ]]; then                                                \
      apt-get -y install libpcl-ros-dev libcv-bridge-dev;                               \
      source navigation/install/setup.bash;                                             \
      source filters/install/setup.bash;                                                \
      git clone -b 1.6.4 --depth=1 https://github.com/ANYbotics/grid_map.git;   \
      cd grid_map;                                                                      \
      unset ROS_DISTRO;                                                                 \
      grep -r c++11 | grep CMakeLists | cut -f 1 -d ':' |                               \
        xargs sed -i -e 's|std=c++11|std=c++17|g';                                      \
      time colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release                         \
        --packages-select grid_map_msgs grid_map_core grid_map_octomap grid_map_sdf     \
        grid_map_costmap_2d grid_map_cv grid_map_ros grid_map_loader;                   \
    fi

######################################
# 6.3) Compile custom message (code provided by Codaero)
#   Note1: Make sure the package name ends with "_msgs".
#   Note2: Use the same package name for both ROS1 and ROS2.
#   See https://github.com/ros2/ros1_bridge/blob/master/doc/index.rst
######################################
RUN if [[ "$ADD_example_custom_msgs" = "1" ]]; then                     \
      git clone https://github.com/TommyChangUMD/custom_msgs.git;       \
      #                                                                 \
      # Compile for ROS1:                                               \
      #                                                                 \
      cd /custom_msgs/custom_msgs_ros1;                                 \
      unset ROS_DISTRO;                                                 \
      time colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release;        \
      #                                                                 \
      # Compile for ROS2:                                               \
      #                                                                 \
      cd /custom_msgs/custom_msgs_ros2;                                 \
      source /opt/ros/humble/setup.bash;                                \
      time colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release;        \
    fi


###########################
# 6.4 Add ROS1 octomap message
###########################
RUN if [[ "$ADD_octomap_msgs" = "1" ]]; then                                    \
    git clone --depth 1 -b 0.3.5 https://github.com/OctoMap/octomap_msgs.git;   \
    cd octomap_msgs/;                                                           \
    unset ROS_DISTRO;                                                           \
    time colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release;                  \
fi

###########################
# 7.) Compile ros1_bridge
###########################
RUN                                                                                             \
    #-------------------------------------                                                      \
    # Apply the ROS2 underlay                                                                   \
    #-------------------------------------                                                      \
    source /opt/ros/humble/setup.bash;                                                          \
    #                                                                                           \
    #-------------------------------------                                                      \
    # Apply additional message / service overlays                                               \
    #-------------------------------------                                                      \
    if [[ "$ADD_ros_tutorials" = "1" ]]; then                                                   \
      # Apply ROS1 package overlay                                                              \
      source ros_tutorials/install/setup.bash;                                                  \
      # Apply ROS2 package overlay                                                              \
      apt-get -y install ros-humble-example-interfaces;                                         \
      source /opt/ros/humble/setup.bash;                                                        \
    fi;                                                                                         \
    #                                                                                           \
    if [[ "$ADD_grid_map" = "1" ]]; then                                                        \
      # Apply ROS1 package overlay                                                              \
      source grid_map/install/setup.bash;                                                       \
      # Apply ROS2 package overlay                                                              \
      apt-get -y install ros-humble-grid-map;                                                   \
      source /opt/ros/humble/setup.bash;                                                        \
    fi;                                                                                         \
    #                                                                                           \
    if [[ "$ADD_example_custom_msgs" = "1" ]]; then                                             \
      # Apply ROS1 package overlay                                                              \
      source /custom_msgs/custom_msgs_ros1/install/setup.bash;                                  \
      # Apply ROS2 package overlay                                                              \
      source /custom_msgs/custom_msgs_ros2/install/setup.bash;                                  \
    fi;                                                                                         \
    #                                                                                           \
    if [[ "$ADD_octomap_msgs" = "1" ]]; then                                                    \
      # Apply ROS1 package overlay                                                              \
      source octomap_msgs/install/setup.bash;                                                   \
      # Apply ROS2 package overlay                                                              \
      apt-get -y install ros-humble-octomap-msgs;                                               \
      source /opt/ros/humble/setup.bash;                                                        \
    fi;                                                                                         \
    #                                                                                           \
    #-------------------------------------                                                      \
    # Finally, build the Bridge                                                                 \
    #-------------------------------------                                                      \
    mkdir -p /ros2_ws/src;                                                       				\
    cd /ros2_ws/src;                                                             				\
    git clone https://github.com/ros2/ros1_bridge.git;  										\
    cd ..;                                                                                   	\
    MEMG=$(printf "%.0f" $(free -g | awk '/^Mem:/{print $2}'));                                 \
    NPROC=$(nproc);  MIN=$((MEMG<NPROC ? MEMG : NPROC));                                        \
    #                                                                                           \
    echo "Please wait...  running $MIN concurrent jobs to build ros1_bridge";                   \
    time MAKEFLAGS="-j $MIN" colcon build --event-handlers console_direct+                      \
      --cmake-args -DCMAKE_BUILD_TYPE=Release

###########################
# 8.) Clean up and source
###########################
RUN apt-get -y clean all

# 创建简单的入口点
RUN echo '#!/bin/bash' > /ros_entrypoint.sh && \
    echo 'set -e' >> /ros_entrypoint.sh && \
    echo 'source /opt/ros/humble/setup.bash' >> /ros_entrypoint.sh && \
    echo 'source /ros2_ws/install/setup.bash' >> /ros_entrypoint.sh && \
    echo 'exec "$@"' >> /ros_entrypoint.sh && \
    chmod +x /ros_entrypoint.sh

WORKDIR /ros2_ws
ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["/bin/bash"]