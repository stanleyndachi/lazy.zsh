#!/usr/bin/env zsh

# lazy.zsh
#
# Copyright 2026 Stanley Ndachi
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# 	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

if [[ -z "${ZSH_VERSION}" ]]; then
	echo "[lazyz]: not in zsh shell!"
	exit 1
fi

if [[ -z "${LAZYZ_DATA_HOME}" ]]; then
	export LAZYZ_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/lazyz"
	mkdir -p "${LAZYZ_DATA_HOME}" &>/dev/null
fi

if [[ -z "${LAZYZ_CACHE_HOME}" ]]; then
	export LAZYZ_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache/}/zsh/lazyz"
fi

if [[ ! -d ${LAZYZ_CACHE_HOME} ]]; then
	mkdir -p "${LAZYZ_CACHE_HOME}" &>/dev/null
fi

if [[ -z "${LAZYZ_UPDATE_REMINDER}" ]]; then
	export LAZYZ_UPDATE_REMINDER=true
fi

# Global Parameter holding the plugin-manager’s capabilities
# 0 – the plugin manager provides the ZERO parameter,
# f - supports the functions/ subdirectory,
# b - supports the bin/ subdirectory,
# u - the unload function,
# U - the @zsh-plugin-run-on-unload call,
# p – the @zsh-plugin-run-on-update call,
# i – the zsh_loaded_plugins activity indicator,
# P – the ZPFX global parameter,
# s – the PMSPEC global parameter itself (i.e.: should be always present).
export PMSPEC=s

# see `README-dev.md`
typeset -g LazyzGhostPluginsArray=()
typeset -g LazyzPluginNameArray=()
typeset -gA LazyzPluginStateMap=()

# /lazyz_debug message
# print a debug message if enabled
#
# Output:
#   gray debug message with caller function name
function /lazyz_debug() {
	print "\e[90m[lazyz]:DEBUG:${funcstack[2]}: ${1}\e[0m"
}

# /lazyz_print message
# print a message
#
# Output:
#   green message
function /lazyz_print() {
	print "\e[32m[lazyz]: ${1}\e[0m"
}

# .lazyz_help
# print this help message and exit
#
# Return:
# - 0 always
function .lazyz_help() {
	print "Usage: lazyz [command] [arg]"
	print ""
	print "Commands:"
	print "    help              print this help message and exit"
	print "    clean NAME        remove the plugin (NAME) or all"
	print "    clean-ghost NAME  remove the ghost plugin (NAME) or all"
	print "    install           install plugins that aren't installed"
	print "    list              list all plugins"
	print "    update            update installed plugins"
	print ""
  return 0
}

# .lazyz_parse_plugin_str plugin_str
# helper to parse a single line and update the LazyzPluginStateMap
#
# Output:
#   an associative array containg:
#     - src: plugin URL or local path
#     - is_installed: (0=missing, 1=installed, 2=local)
#     - branch: git branch (if specified)
#     - commit: commit hash (if specified)
#     - tag: git tag (if specified)
#     - build: build commands (if specified)
#
# Return:
# - 0 when successful
# - 1 when plugin_str is empty or invalid
function .lazyz_parse_plugin_str() {
	local plugin_str="${1}"
	if [[ -z "${plugin_str}" ]]; then
		/lazyz_debug "missing 'plugin_str'"
		return 1
	fi

  # split the plugin_str into an array (respects quoting)
  local -a parts
  parts=("${(z)plugin_str}")

	# plugin_src - first positional arg
  local plugin_src="${parts[1]}"
  if [[ -z "${plugin_src}" ]]; then
    /lazyz_debug "missing 'plugin_src'"
	  return 1
  fi

  local plugin_name="${plugin_src##*/}"
  plugin_name="${plugin_name%.git}"
  LazyzPluginStateMap[${plugin_name}:src]="${plugin_src}"
  LazyzPluginStateMap[${plugin_name}:is_installed]=0 # missing
	
	# parse options
	for opt in "${parts[@]:1}"; do
		case "${opt}" in
		branch=*)
			LazyzPluginStateMap[${plugin_name}:branch]="${opt#branch=}"
			;;
		commit=*)
			local commit="${opt#commit=}"
			LazyzPluginStateMap[${plugin_name}:commit]="${commit:0:7}"
			;;
		tag=*)
			LazyzPluginStateMap[${plugin_name}:tag]="${opt#tag=}"
			;;
		build=*)
			LazyzPluginStateMap[${plugin_name}:build]="${opt#build=}"
			;;
    local=true)
        # local=false silently does nothing
        LazyzPluginStateMap[${plugin_name}:is_installed]=2 # local
			;;
		*)
			/lazyz_debug "unknown option '${opt}' in '${plugin_str}'"
			;;
		esac
	done

	# checks installation status
  if [[ ${LazyzPluginStateMap[${plugin_name}:is_installed]} -ne 2 ]]; then
    if [[ -d "${LAZYZ_DATA_HOME}/${plugin_name}/.git" ]]; then
      LazyzPluginStateMap[$plugin_name:is_installed]=1 # installed
    fi

    # If it doesn't look like a full URL, assume GitHub
		local url="${LazyzPluginStateMap[${plugin_name}:src]}"
		if [[ $url != git://* && $url != https://* && $url != http://* && $url != ssh://* && $url != git@*:*/* ]]; then
		  url="https://github.com/${url%.git}.git"
		fi
		LazyzPluginStateMap[${plugin_name}:src]="$url"
  fi

  REPLY=${plugin_name}
	unset -v plugin_str parts plugin_src plugin_name
	return 0
}

# .lazyz_parse_plugins
# parse LAZYZ_PLUGINS array
#
# Return:
# - 0 when successful
# - 1 otherwise
function .lazyz_parse_plugins() {
  LazyzPluginNameArray=()
  for plugin_entry in "${LAZYZ_PLUGINS[@]}"; do
    if ! .lazyz_parse_plugin_str "${plugin_entry}"; then
      /lazyz_debug "failed to parse '${plugin_entry}'"
      continue
    fi
    LazyzPluginNameArray+=("${REPLY}")
  done
  return 0
}

# .lazyz_detect_ghost_plugins
# identify ghost plugins i.e installed on disk but not declared in LAZYZ_PLUGINS
#
# Return:
# - 0 when successful
# - 1 otherwise
function .lazyz_detect_ghost_plugins() {
  local -A declared_plugins
  for plugin in "${LazyzPluginNameArray[@]}"; do
    declared_plugins[$plugin]=1
  done

  local -a installed_plugins
  installed_plugins=(${LAZYZ_DATA_HOME}/*(N/))
  LazyzGhostPluginsArray=()
  for dir in "${installed_plugins[@]}"; do
    local name="${dir:t}"
    [[ -n "${declared_plugins[$name]}" ]] && continue

    # ensure it looks like a plugin
    if [[ -d "${dir}/.git" || -n "${dir}"/*.plugin.zsh(N) ]]; then
      LazyzGhostPluginsArray+=("$name")
    fi
  done
  unset declared_plugins installed_plugins
  return 0
}

# .lazyz_list
# list all plugins (missing, installed and local)
#
# Output:
#   fancy plugins table
#
# Return:
# - 0 when successful
# - 1 otherwise
function .lazyz_list() {
	/lazyz_print "lazy.zsh plugin manager\n"

  # Table Header
  # Status (6) | Name (30) | Branch (8) | Version
	printf " %-6s | %-30s | %-8s | %s \n" "Status" "Name" "Branch" "Version"
	print "================================================================"

  .lazyz_parse_plugins
	for plugin_name in "${LazyzPluginNameArray[@]}"; do
		printf " %-6s | %-30s | %-8s | %s\n" \
			"${LazyzPluginStateMap[${plugin_name}:is_installed]}" \
			"${plugin_name}" \
			"${LazyzPluginStateMap[${plugin_name}:branch]}" \
			"${LazyzPluginStateMap[${plugin_name}:commit]:-${LazyzPluginStateMap[${plugin_name}:tag]}}"
	done

  .lazyz_detect_ghost_plugins
  for plugin_name in "${LazyzGhostPluginsArray[@]}"; do
      printf " %-6s | %-30s | %-8s | %s\n" \
        "3" \
        "${plugin_name}" \
        "-" \
        "-"
	done

	/lazyz_print "Plugins status: 0=missing, 1=installed, 2=local, 3=ghost"
	/lazyz_print "Run 'lazyz install' to install missing plugins"
	return 0
}

# .lazyz_build_plugin plugin_name
# run build command for the plugin
#
# Return:
# - 0 when successful
# - 1 otherwise
function .lazyz_build_plugin() {
	local plugin_name="${1}"
	if [[ -z "${plugin_name}" ]]; then
		/lazyz_debug "missing 'plugin_name'"
		return 1
	fi

  local build_cmd="${LazyzPluginStateMap[${plugin_name}:build]}"
  local plugin_dir="${LAZYZ_DATA_HOME}/${plugin_name}"
  if [[ -z "${build_cmd}" ]] || [[ ! -d "${plugin_dir}" ]]; then
    return 1
  fi

  /lazyz_debug "executing build command '${build_cmd}' for ${plugin_name}"
  (
    cd "${plugin_dir}" || exit 1
    zsh -c "${build_cmd}"
  )

  if [[ $? -ne 0 ]]; then
    /lazyz_print "build failed for ${plugin_name}"
    return 1
  fi
  /lazyz_debug "build succeeded for ${plugin_name}"
  return 0
}

# .lazyz_update
# update all installed plugins
#
# Return:
# - 0 when successful
# - 1 otherwise
function .lazyz_update() {
  .lazyz_parse_plugins
	for plugin_name in "${LazyzPluginNameArray[@]}"; do
    # Only update if status is 1 (installed git repo)
    if [[ "${LazyzPluginStateMap[${plugin_name}:is_installed]}" -eq 1 ]]; then
      local plugin_dir="${LAZYZ_DATA_HOME}/${plugin_name}"
			local tag="${LazyzPluginStateMap[${plugin_name}:tag]}"
			local commit="${LazyzPluginStateMap[${plugin_name}:commit]}"
			local branch="${LazyzPluginStateMap[${plugin_name}:branch]}"

			if [[ -n "${tag}" || -n "${commit}" ]]; then
				/lazyz_debug "Skipping... ${plugin_name} is locked to a version '${tag:-commit}'"
				continue
			fi

			local last_head current_head
			if [[ -n "${branch}" ]]; then
				git -C "${plugin_dir}" checkout "${branch}" &>/dev/null
			fi
			last_head=$(git -C "${plugin_dir}" rev-parse HEAD)
      /lazyz_debug "Updating ${plugin_name}..."

			if (git -C "${plugin_dir}" pull --quiet --rebase --stat --autostash); then
        /lazyz_debug "rebasing ${plugin_name} on remote ${branch:-default}"
				current_head=$(git -C "${plugin_dir}" rev-parse HEAD 2>/dev/null)
				# compare the last head and the current head(after a `git pull`)
				if [[ "${last_head}" == "${current_head}" ]]; then
					/lazyz_print "${plugin_name} is already up-to-date"
				else
					/lazyz_print "${plugin_name} has been updated"
          .lazyz_build_plugin "${plugin_name}"
				fi
			else
				/lazyz_print "Error updating ${plugin_name}. Try again later?"
			fi
			unset plugin_dir tag commit branch last_head current_head
		fi
	done
  return 0
}

# .lazyz_install
# install new plugins define in LAZYZ_PLUGINS array
#
# Return:
# - 0 when successful
# - 1 otherwise
function .lazyz_install() {
  .lazyz_parse_plugins
	for plugin_name in "${LazyzPluginNameArray[@]}"; do
    if [[ "${LazyzPluginStateMap[${plugin_name}:is_installed]}" -eq 0 ]]; then
      local plugin_dir="${LAZYZ_DATA_HOME}/${plugin_name}"
      local -a git_args=(clone --recursive)
			local tag="${LazyzPluginStateMap[${plugin_name}:tag]}"
			local commit="${LazyzPluginStateMap[${plugin_name}:commit]}"
			local branch="${LazyzPluginStateMap[${plugin_name}:branch]}"

      # use shallow clone if no specific commit/tag is requested
      if [[ -z "${tag}" && -z "${commit}" ]]; then
          git_args+=(--depth=1)
      fi

      # if branch is specified
			if [[ -n "${branch}" ]]; then
        git_args+=(-b "${branch}")
			fi

      if git "${git_args[@]}" "${LazyzPluginStateMap[${plugin_name}:src]}" "${plugin_dir}"; then
        # if tag/commit is specified
        if [[ -n "${tag}" ]]; then
          git -C "${plugin_dir}" checkout --detach "refs/tags/${tag}"
        elif [[ -n "${commit}" ]]; then
          git -C "${plugin_dir}" checkout "${commit}"
        fi
        .lazyz_build_plugin "${plugin_name}"
      else
        /lazyz_print "failed to install ${plugin_name}"
        continue
      fi
      unset -v plugin_dir git_args tag commit branch
		else
			/lazyz_debug "${plugin_name} is already installed"
		fi
	done
  return 0
}

# .lazyz_clean NAME | all
# remove the plugin (NAME) or all
#
# Return:
# - 0 when successful
# - 1 otherwise
function .lazyz_clean() {
	local -a remove_args=("${@}")
	/lazyz_debug "${remove_args[*]}"

	if [[ -z "${remove_args[2]}" ]]; then
		/lazyz_print "missing operand"
		/lazyz_print "Try 'lazyz help' for more information"
		return 1
	fi

	if [[ "${remove_args[2]}" == "all" ]]; then
    if (( ${#remove_args[@]} > 2 )); then
      /lazyz_print "'all' cannot be combined with plugin names"
      return 1
    fi
		rm -rf --interactive=never "${LAZYZ_DATA_HOME:?}/*"
		/lazyz_print "all plugins removed"
		return 0
	fi

  .lazyz_parse_plugins
	for remove_arg in "${remove_args[@]:1}"; do
		if [[ "${LazyzPluginStateMap[${remove_arg}:is_installed]}" -eq 1 ]]; then
			rm -rf --interactive=once "${LAZYZ_DATA_HOME:?}/${remove_arg}"
		else
			/lazyz_print "'${remove_arg}' doesn't exists or is not installed"
		fi
	done
	unset -v remove_args
	/lazyz_print "Run 'lazyz list' to see installed plugins"
	return 0
}

# .lazyz_clean-ghost NAME | all
# remove the ghost plugin (NAME) or all
#
# Return:
# - 0 when successful
# - 1 otherwise
function .lazyz_clean-ghost() {
	local -a remove_args=("${@}")
	/lazyz_debug "${remove_args[*]}"

	if [[ -z "${remove_args[2]}" ]]; then
		/lazyz_print "missing operand"
		/lazyz_print "Try 'lazyz help' for more information"
		return 1
	fi

  .lazyz_detect_ghost_plugins
  if [[ ${#LazyzGhostPluginsArray[@]} == 0 ]]; then
    /lazyz_print "no ghost plugins found"
    return 0
  fi

	if [[ "${remove_args[2]}" == "all" ]]; then
    if (( ${#remove_args[@]} > 2 )); then
      /lazyz_print "'all' cannot be combined with plugin names"
      return 1
    fi
    for plugin in "${LazyzGhostPluginsArray[@]}"; do
        rm -rf --interactive=never "${LAZYZ_DATA_HOME:?}/${plugin}"
    done
		/lazyz_print "all ghost plugins removed"
		return 0
	fi

  local -A ghosts
  for plugin in "${LazyzGhostPluginsArray[@]}"; do
    ghosts[$plugin]=1
  done

  for plugin in "${remove_args[@]:1}"; do
    if [[ -n "${ghosts[$plugin]}" ]]; then
      rm -rf --interactive=once "${LAZYZ_DIR:?}/${plugin}"
    else
      /lazyz_print "'${plugin}' is not a ghost plugin"
    fi
  done
	unset -v remove_args
	/lazyz_print "Run 'lazyz list' to see installed plugins"
	return 0
}

# shameless copy from "autoupdate-oh-my-zsh-plugins"
# <https://github.com/tamcore/autoupdate-oh-my-zsh-plugins/blob/master/autoupdate.plugin.zsh>
zmodload zsh/datetime

function .lazyz_current_epoch() {
	print $((EPOCHSECONDS / 60 / 60 / 24))
}

function .lazyz_remind_user() {
	if [[ "$LAZYZ_UPDATE_REMINDER" != "true" ]]; then
		return 0 # reminder disabled
	fi

	local epoch_diff choice cache_file="${LAZYZ_CACHE_HOME}/lazyz_epoch"
	if [ -r "${cache_file}" ]; then
		source "${cache_file}"
	fi

	if [[ -z "$LAST_EPOCH" ]]; then
		print "LAST_EPOCH=$(.lazyz_current_epoch)" >|"${cache_file}"
		return 0
	fi

	epoch_diff=$(($(.lazyz_current_epoch) - LAST_EPOCH))
	if [[ $epoch_diff -ge "${LAZYZ_UPDATE_INTERVAL:-14}" ]]; then
		/lazyz_print "It's time to update your plugins"
		/lazyz_print "Would you like to check for updates now? [y/N] "
		read choice
		case "${choice}" in
		Y | y)
      if .lazyz_update; then
	    	print "LAST_EPOCH=$(.lazyz_current_epoch)" >|"${cache_file}"
      fi
			;;
		*) # default [No]
		  print "LAST_EPOCH=$(.lazyz_current_epoch)" >|"${cache_file}"
			/lazyz_print "You can run 'lazyz update' manually anytime"
			;;
		esac
		unset choice
	fi
	unset -v LAST_EPOCH epoch_diff cache_file
}

# main program
.lazyz_remind_user
unset -f .lazyz_current_epoch .lazyz_remind_user

lazyz() {
	local cmd="${1}"
	if [[ -z "${cmd}" ]]; then
		.lazyz_help
		return 1
	fi
	if functions ".lazyz_${cmd}" >/dev/null; then
		".lazyz_${cmd}" "${@}"
	else
		/lazyz_print "command '${cmd}' not found :("
		return 1
	fi
}
