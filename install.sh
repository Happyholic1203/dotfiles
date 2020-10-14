#!/usr/bin/env bash

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [vim|restore]

Options:
    -h|--help: show this usage
    --with-ycm: install with YCM support
    --with-bashit: install with bash-it support
    --update: update submodules to latest versions
    --with-jsxhint: install with jsxhint support
    --with-ranger: install with ranger support
EOF
    exit 0
}

red='\033[91m'
green='\033[92m'
blue='\033[94m'
yellow='\033[93m'
white='\033[0m'

say() {
    if [ "$(ps -p $$ -ocomm=)" = "bash" ]; then
        echo -e "$1"
    else
        echo "$1"
    fi
}

info() {
    say "${blue}[+]${white} $1"
}

warn() {
    say "${yellow}[+]${white} $1"
}

error() {
    say "${red}[-]${white} $1"
}

get_unified_os_name() {
    case "$OSTYPE" in
        darwin*)
            echo Darwin
            ;;
        linux*)
            issue=`cat /etc/issue`
            if cat /etc/issue | grep -i ubuntu >/dev/null 2>&1; then
                echo Ubuntu
            elif cat /etc/issue | grep -iE 'debian|kali' >/dev/null 2>&1; then
                echo Debian
            fi
            ;;
        *)
            echo Unknown
            return 1
            ;;
    esac
    return 0
}

function link_file {
    source="${PWD}/$1"
    target="${HOME}/${1/_/.}"

    if [ -e "${target}" ] && [ ! -L "${target}" ]; then
        mv $target $target.df.bak
    fi

    ln -sf ${source} ${target}
}

function unlink_file {
    source="${PWD}/$1"
    target="${HOME}/${1/_/.}"

    if [ -e "${target}.df.bak" ] && [ -L "${target}" ]; then
        unlink ${target}
        mv $target.df.bak $target
    elif [ -L "${target}" ]; then
        unlink ${target}
    fi
}

has() {
    hash $1 >/dev/null 2>&1 && return 0
    if hash brew >/dev/null 2>&1; then
        brew ls --versions $1 >/dev/null 2>&1 && return 0
    elif hash dpkg >/dev/null 2>&1; then
        if dpkg -s $1 2>/dev/null | grep '^Status' | grep installed; then
            return 0
        fi
    fi
    return 1
}

function install_prerequisites {
    if [ "$OS" = "Darwin" ]; then
        if ! which brew; then
            error 'I need homebrew to install dependencies'
            error 'If you continue, some functions may not work properly'
            while true; do
                read -p '> Continue anyway? (yes or no) ' ans
                case $ans in
                    [yY]*)
                        info 'Continuing'
                        break
                        ;;
                    [nN]*)
                        info 'Aborting...'
                        exit 1
                        ;;
                    *)
                        error "Invalid answer: $ans"
                        ;;
                esac
            done
        fi
        has ctags || brew install ctags
        has ag || brew install the_silver_searcher
        has fd || brew install fd
        has rg || brew install ripgrep
    elif has apt-get; then
        sudo apt-get update
        sudo apt-get install -yq --force-yes ctags silversearcher-ag

        # install fd & rg
        tmp=$(mktemp -d)
        for repo in BurntSushi/ripgrep sharkdp/fd; do
            name=$(basename $repo)
            has $name && continue
            url=$(curl -s https://api.github.com/repos/$repo/releases/latest|\
                grep -o "browser_download_url.*${name}_.*_amd64.deb"|\
                grep -o 'https://.*_amd64.deb')
            wget -P "$tmp" "$url"
        done
        test -n "$(ls -A $tmp/)" && sudo dpkg -i $tmp/*.deb
        rm -rf $tmp
    else
        warn 'Please install ctags, silversearcher by hand'
    fi

    if [ ! -d ~/.fzf ]; then
        git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
        ~/.fzf/install --all
    fi
}

install_jsxhint() {
    if ! has npm ; then
        if has brew; then
            brew install npm
        elif has apt-get; then
            sudo apt-get install npm
        else
            error "No available package manager to install npm: skipping jsxhint"
            return 1
        fi
    fi

    if ! has jsxhint ; then
        npm install -g eslint babel-eslint eslint-plugin-react
    fi
}

install_ycm() {
    pushd _vim/bundle/YouCompleteMe
    info "Installing dependencies for YCM... (Assuming python-dev, xz-utils are installed)"
    for x in cmake clang; do
        if ! has $x; then
            info "Installing $x..."
            if has brew; then
                brew install $x
            elif has apt-get; then
                apt-get install -yq --force-yes $x
            else
                error "Missing dependency: $x (Please install by hand)"
                return 1
            fi
        fi
    done

    info "Installing YCM..."
    ./install.py --clang-completer
    rm -f ./third_party/ycmd/clang_archives/clang*
    popd
}

install_ranger() {
    d=`mktemp -d`
    pushd $d
    wget http://nongnu.org/ranger/ranger-stable.tar.gz
    tar xvf ranger-stable.tar.gz
    rm -f ranger-stable.tar.gz
    pushd ranger-*
    make install
    popd
    popd
    rm -rf $d
}

install_bashit() {
    mv ~/.bashrc ~/.bashrc.before-bash-it.bak
    pushd ~/.bash-it
    ./install.sh -s
    . ~/.bash-it/bash_it.sh
    for plugin in alias-completion autocd base fzf gitstatus short-docker short-git; do
        bash-it enable plugin $plugin
    done
    bash-it enable alias vim
    popd
}

main() {
    OS=`get_unified_os_name`

    opt_with_ycm=0
    opt_with_bashit=0
    opt_update=0
    opt_with_jsxhint=0
    opt_with_ranger=0

    target=all

    while [ $# -gt 0 ]; do
        case $1 in
            --with-ycm)
                opt_with_ycm=1
                ;;
            -n|--no-update)  # deprecated
                opt_update=0
                ;;
            --update)
                opt_update=1
                ;;
            --with-bashit)
                opt_with_bashit=1
                ;;
            --with-jsxhint)
                opt_with_jsxhint=1
                ;;
            --with-ranger)
                opt_with_ranger=1
                ;;
            -h|--help)
                usage
                return 0
                ;;
            -*|--*)
                usage
                return 1
                ;;
            *)
                target=$1
                ;;
        esac
        shift
    done

    case $target in
        vim)
            info "Installing vim settings..."
            for f in _vim*; do
                link_file $f
            done
            ;;
        restore)
            info "Restoring..."
            for f in _*; do
                unlink_file $f
            done
            ;;
        all)
            info "Installing all..."
            install_prerequisites
            for f in _*; do
                link_file $f
            done
            ;;
        *)
            error "Invalid target: $target"
            usage
            return 1
            ;;
    esac

    if [ $opt_with_ycm -eq 1 ]; then
        info 'Including YCM submodule...'
    else
        info 'Excluding YCM submodule...'
        git submodule deinit _vim/bundle/YouCompleteMe >/dev/null 2>&1 || true
        git rm -r _vim/bundle/YouCompleteMe >/dev/null 2>&1 || true
    fi

    if [ $opt_with_bashit -eq 1 ] && [ ! -d ~/.bash-it ]; then
        info 'Including bash-it submodule...'
    else
        info 'Excluding bash-it submodule...'
        git submodule deinit _bash-it >/dev/null 2>&1 || true
        git rm -r _bash-it >/dev/null 2>&1 || true
    fi

    submodules=`git submodule | awk '{print $2}'`
    for x in _vim/bundle/*; do
        if ! echo "$submodules" | grep $x >/dev/null 2>&1; then
            info "Removing unused submodule: $x"
            rm -rf $x
        fi
    done

    git submodule update --init --recursive

    if [ $opt_with_ycm -eq 1 ]; then
        install_ycm || error "Failed to install YCM"
    fi

    if [ $opt_with_jsxhint -eq 1 ]; then
        install_jsxhint
    fi

    if [ $opt_with_ranger -eq 1 ] && ! has ranger; then
        install_ranger
    fi

    if [ $opt_with_bashit -eq 1 ]; then
        install_bashit
    fi

    if [ $opt_update -eq 1 ]; then
        info "Updating submodules to latest versions..."
        git submodule foreach --recursive git pull origin master
    fi
}

main $@

# Prerequisites of YouCompleteMe
# - cmake
# - build-essential
