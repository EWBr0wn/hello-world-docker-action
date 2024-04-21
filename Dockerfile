# Set the base image to use for subsequent instructions
FROM rockylinux:8.9

# Install elements for building RPMs
RUN yum install --setopt=tsflags=nodocs -y \
      rpm-build \
      rpmdevtools \
      rpmlint \
      redhat-rpm-config \
      rsync \
      yum-utils \
    && yum clean all \
    && rm -rf /var/cache/yum \
    && echo '%_topdir /usr/src/rpmbuild' > ~/.rpmmacros \
    && rpmdev-setuptree

# Set the working directory inside the container
WORKDIR /usr/src

# Copy any source file(s) required for the action
COPY entrypoint.sh .

# Configure the container to be run as an executable
ENTRYPOINT ["/usr/src/entrypoint.sh"]
