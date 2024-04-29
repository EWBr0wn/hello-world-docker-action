#!/bin/sh -l

if [ -f /etc/os-release ] ; then
  . /etc/os-release
  echo "::notice file=entrypoint.sh,line=6::${PRETTY_NAME}"
fi

if [ -n "${PRETTY_NAME}" ] ; then
  echo "# List env vars"
  env | sort
  echo
fi

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

  # consider input parameters that control '-v', '-vv', and '--define "debug_package %{nil}"' independently
  echo "# Build RPM"
  rpmbuild -ba --define "debug_package %{nil}" -v ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}

  echo "# List output RPMs"
  ls -lR $(rpm --eval "%_rpmdir")
  echo "# List expected RPMs"
  rpmspec --query --rpms ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))'
  tmp_rpm_array=$(rpmspec --query --rpms ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))')

  echo "# List output SRPM"
  ls -lR $(rpm --eval "%_srcrpmdir")
  echo "# List expected SRPM"
  if [ "$(rpmspec --query --srpm --queryformat="%{arch}" ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME})" = "src" ] ; then
    rpmspec --query --srpm ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))'
    tmp_srpm_array=$(rpmspec --query --srpm ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))')
  else
    ## Potential bug in rpmspec where the Source RPM does not have arch=src
    rpmspec --query --srpm --queryformat="%{name}-%{version}-%{release}.src" ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME}
    tmp_srpm_array=$(rpmspec --query --srpm ${RPMBUILDSPECSDIR}/${REPO_SPEC_FILENAME} | jq -R -s -c 'split("\n") | map(select(length>0))')
    ##
  fi

  # If all is good so far, create output directory
  if [ ! -d ${GITHUB_WORKSPACE}/output ] ; then
    mkdir -v ${GITHUB_WORKSPACE}/output
  fi

  # Copy output RPMs
  rsync --archive --verbose $(rpm --eval "%_rpmdir") $(rpm --eval "%_srcrpmdir") ${GITHUB_WORKSPACE}/output/
  # make temp file
  TMPFILE=$(mktemp -q /tmp/.filearray-egrep.XXXXXX)
  echo ${tmp_rpm_array} | jq -r .[] | awk '{print "/" $1}'
  echo ${tmp_rpm_array} | jq -r .[] | awk '{print "/" $1}' > ${TMPFILE}
  echo "# finding files"
  find output -type f
  echo "## find files matching the following"
  cat ${TMPFILE}
  echo "# make rpm_array"
  find output -type f | egrep -f ${TMPFILE} | jq -R -s -c 'split("\n") | map(select(length>0))'
  rpm_array=$(find output -type f | egrep -f ${TMPFILE} | jq -R -s -c 'split("\n") | map(select(length>0))')
  echo ${tmp_srpm_array} | jq -r .[] | awk '{print "/" $1}'
  echo ${tmp_srpm_array} | jq -r .[] | awk '{print "/" $1}' > ${TMPFILE}
  echo "## find files matching the following"
  cat ${TMPFILE}
  echo "# make srpm_array"
  find output -type f | egrep -f ${TMPFILE} | jq -R -s -c 'split("\n") | map(select(length>0))'
  srpm_array=$(find output -type f | egrep -f ${TMPFILE} | jq -R -s -c 'split("\n") | map(select(length>0))')

  # set outputs
  # built_rpm_array:
  #  description: 'JSON array of built RPM files'
  echo "built_rpm_array=${rpm_array}" >>"$GITHUB_OUTPUT"
  # built_srpm_array:
  #  description: 'JSON array of SRPM'
  echo "built_srpm_array=${srpm_array}" >>"$GITHUB_OUTPUT"
  
  # description: 'Content-type for Upload'
  echo "rpm_content_type=application/x-rpm" >>"$GITHUB_OUTPUT"
fi

# Use INPUT_<INPUT_NAME> to get the value of an input
GREETING="Hello, $INPUT_WHO_TO_GREET! from $PRETTY_NAME"

# Use workflow commands to do things like set debug messages
echo "::notice file=entrypoint.sh,line=125::$GREETING"

# Write outputs to the $GITHUB_OUTPUT file
echo "greeting=$GREETING" >>"$GITHUB_OUTPUT"

exit 0
