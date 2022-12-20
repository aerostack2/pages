#!/bin/bash

# set -x
set -e

repo_dir=$GITHUB_WORKSPACE/main/$INPUT_REPOSITORY_PATH
as2_dir=$GITHUB_WORKSPACE/aerostack2/
doc_dir=$repo_dir/$INPUT_DOCUMENTATION_PATH

echo ::group:: Initialize various paths
echo Workspace: $GITHUB_WORKSPACE
echo Repository: $repo_dir
echo Documentation: $doc_dir
echo ::endgroup::

# The actions doesn't depends on any images,
# so we have to try various package manager.
echo ::group:: Installing Sphinx

echo Installing sphinx via pip
if [ -z "$INPUT_SPHINX_VERSION" ] ; then
    python3 -m pip install -U sphinx
else
    python3 -m pip install -U sphinx==$INPUT_SPHINX_VERSION
fi

echo Adding user bin to system path
PATH=$HOME/.local/bin:$PATH
if ! command -v sphinx-build &>/dev/null; then
    echo Sphinx is not successfully installed
    exit 1
else
    echo Everything goes well
fi

echo ::endgroup::

if [ ! -z "$INPUT_REQUIREMENTS_PATH" ] ; then
    echo ::group:: Installing requirements
    if [ -f "$repo_dir/$INPUT_REQUIREMENTS_PATH" ]; then
        echo Installing python requirements
        python3 -m pip install -r "$repo_dir/$INPUT_REQUIREMENTS_PATH"
    else
        echo No requirements.txt found, skipped
    fi
    echo ::endgroup::
fi

echo ::group:: Checking modules list
if [ ! -z "$INPUT_AEROSTACK2_MODULES" ]; then 
    INPUT_AEROSTACK2_MODULES="$(echo "$INPUT_AEROSTACK2_MODULES" | sed 's/ //g')"
    echo $INPUT_AEROSTACK2_MODULES
    arrModules=(${INPUT_AEROSTACK2_MODULES//,/ })
fi
echo ::endgroup::

source /opt/ros/$ROS_DISTRO/setup.bash
mkdir -p $doc_dir/_user/temp_ws/src # In case there is a python project to be built for autodoc to generate documentation

shopt -s dotglob
shopt -s nullglob
array=(*/)

echo ::group:: Organizing workspace
for dir in "${arrModules[@]}"; do
    shopt -s globstar
    while true; do
        for d in ./**/$dir ; do
            module_dir=$d
            break 2 # escape both loops
        done
        echo "'$d' not found, please try again."
    done
    echo "rest of script etc"
    shopt -u globstar
    echo $module_dir
    if [[ -f ""$module_dir"/setup.py" ]]; then # This is a python project    
        echo ""$module_dir"/ is a python project, performing compilation";
        cp -r "$module_dir"/ $doc_dir/_user/temp_ws/src
        cd $doc_dir/_user/temp_ws/
        colcon build --symlink-install
        source install/setup.bash
        cd -
        sphinx-apidoc -o $doc_dir/_user/temp_ws/src/"$dir"/docs/source $doc_dir/_user/temp_ws/src/"$dir"/"$dir"/

    elif [[ -f ""$module_dir"/doxygen.dox" ]]; then # This is a c++ project, no need to compile
        echo ""$module_dir"/ is a c++ project, performing doxygen build";
        cp -r "$module_dir" $doc_dir/_user
        cd $doc_dir/_user/$dir/
        doxygen doxygen.dox
        cd -
    fi;
    done
echo ::endgroup::

shopt -u dotglob
shopt -u nullglob

echo ::group:: Creating temp directory
tmp_dir=$(mktemp -d -t pages-XXXXXXXXXX)
echo Temp directory \"$tmp_dir\" is created
echo ::endgroup::

echo ::group:: Running Sphinx builder
if ! sphinx-build -b html "$doc_dir" "$tmp_dir" $INPUT_SPHINX_OPTIONS; then
    echo ::endgroup::
    echo ::group:: Dumping Sphinx error log 
    for l in $(ls /tmp/sphinx-err*); do
        cat $l
    done
    exit 1
fi
echo ::endgroup::

echo ::group:: Setting up git repository
echo Setting up git configure
cd $repo_dir
git config --local user.email "action@github.com"
git config --local user.name "GitHub Action"
git stash
echo Setting up branch $INPUT_TARGET_BRANCH
branch_exist=$(git ls-remote --heads origin refs/heads/$INPUT_TARGET_BRANCH)
if [ -z "$branch_exist" ]; then
    echo Branch doesn\'t exist, create an empty branch
    git checkout --force --orphan $INPUT_TARGET_BRANCH
else
    echo Branch exists, checkout to it
    git checkout --force $INPUT_TARGET_BRANCH
fi
git clean -fd
echo ::endgroup::

echo ::group:: Committing HTML documentation
cd $repo_dir
echo Deleting all file in repository
rm -vrf *
echo Copying HTML documentation to repository
# Remove unused doctree
rm -rf $tmp_dir/.doctrees
cp -vr $tmp_dir/. $INPUT_TARGET_PATH
if [ ! -f "$INPUT_TARGET_PATH/.nojekyll" ]; then
    # See also sphinxnotes/pages#7
    echo Creating .nojekyll file
    touch "$INPUT_TARGET_PATH/.nojekyll"
fi
echo Adding HTML documentation to repository index
git add $INPUT_TARGET_PATH
echo Recording changes to repository
git commit --allow-empty -m "Add changes for $GITHUB_SHA"
echo ::endgroup::
