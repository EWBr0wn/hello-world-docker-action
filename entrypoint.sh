#!/bin/sh -l

if [ -f /etc/os-release ] ; then
  . /etc/os-release
fi

echo "# List env vars"
env | sort
echo

echo "# List recursively /usr/src"
ls -lhR /usr/src
echo

echo "# List GITHUB_WORKSPACE: ${GITHUB_WORKSPACE}"
ls -lhR ${GITHUB_WORKSPACE}
echo

echo "# user home directory ~/.rpmmacros"
if [ ! -f ~/.rpmmacros ] ; then
  echo '%_topdir /usr/src/rpmbuild' > ~/.rpmmacros
fi
cat ~/.rpmmacros
echo

echo "INPUT_SPEC_FILE: ${INPUT_SPEC_FILE}"
if [ -n "${INPUT_SPEC_FILE}" ] ; then
  REPO_SPEC_DIR=$(dirname ${INPUT_SPEC_FILE})
  REPO_SPEC_FILENAME=$(basename ${INPUT_SPEC_FILE})
  RPMBUILDSPECSDIR=$(rpm --eval "%_specdir")
  RPMBUILDSOURCEDIR=$(rpm --eval "%_sourcedir")
  cp --archive --verbose ${GITHUB_WORKSPACE}/${INPUT_SPEC_FILE} ${RPMBUILDSPECSDIR}/

  if [ -n "${ADDITIONAL_REPOS}" ] ; then
    echo "${ADDITIONAL_REPOS}" | jq -r .[]
    for repo in $(echo "${ADDITIONAL_REPOS}" | jq -r .[]) ; do
      yum-config-manager --enable ${repo}
      ## Correct answer is to test for URL or string
      # yum install -y ${repo}
    done
  fi

  #echo "# rpmlint the SPEC_FILE:"
  #rpmlint ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
  #retval=$?
  #if [ ${retval} -gt 0 ] ; then
  #  exit ${retval}
  #fi

  echo "# List SPEC_FILE (${REPO_SPEC_FILENAME}) sources: ${INPUT_SPEC_FILE}"
  spectool --sources ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
  for f in $(spectool --sources ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | egrep -v 'http[s]*://|ftp://' | awk '{print $2}') ; do
    cp --archive --verbose ${GITHUB_WORKSPACE}/${REPO_SPEC_DIR}/../SOURCES/${f} ${RPMBUILDSOURCEDIR}/
  done

  echo "# List SPEC_FILE (${REPO_SPEC_FILENAME}) patches: ${INPUT_SPEC_FILE}"
  spectool --patches ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
  for p in $(spectool --patches ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | egrep -v 'http[s]*://|ftp://' | awk '{print $2}') ; do
    cp --archive --verbose ${GITHUB_WORKSPACE}/${REPO_SPEC_DIR}/../SOURCES/${p} ${RPMBUILDSOURCEDIR}/
  done

  echo "# Fetch Source and Patches files from URLs"
  spectool --get-files --sourcedir ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}

  echo "# Using yum-builddep from yum-utils to install all the build dependencies for a package"
  yum-builddep -y ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}

  echo "# Build RPM"
  rpmbuild -ba -v ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}

  echo "# List output RPMs"
  ls -lR $(rpm --eval "%_rpmdir")
  echo "# List expected RPMs"
  rpmspec --query --rpms ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))'

  echo "# List output SRPM"
  ls -lR $(rpm --eval "%_srcrpmdir")
  echo "# List expected SRPM"
  rpmspec --query --srpm ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))'

  # If all is good so far, create output directory
  if [ ! -d ${GITHUB_WORKSPACE}/output ] ; then
    mkdir -v ${GITHUB_WORKSPACE}/output
  fi

  # Copy output RPMs
  rsync --archive --verbose $(rpm --eval "%_rpmdir") $(rpm --eval "%_srcrpmdir") ${GITHUB_WORKSPACE}/output/

  # set outputs
  # source_rpm_path:
  #  description: 'path to Source RPM file'
  # source_rpm_dir_path:
  #  description: 'path to SRPMS directory'
  # source_rpm_name:
  #  description: 'name of Source RPM file'
  # rpm_dir_path:
  #  description: 'path to RPMS directory'
  
  # description: 'Content-type for Upload'
  echo "rpm_content_type=application/x-rpm" >>"$GITHUB_OUTPUT"
fi

# Use INPUT_<INPUT_NAME> to get the value of an input
GREETING="Hello, $INPUT_WHO_TO_GREET! from $PRETTY_NAME"

# Use workflow commands to do things like set debug messages
echo "::notice file=entrypoint.sh,line=7::$GREETING"

# Write outputs to the $GITHUB_OUTPUT file
echo "greeting=$GREETING" >>"$GITHUB_OUTPUT"

exit 0
