#!/usr/bin/env bash
# gcloud-ps1: gcloud のアクティブな構成(アカウント / プロジェクト)をプロンプトに表示する
#
# https://github.com/motuneko253/gcloud-ps1
# バージョン: 0.1.0 / ライセンス: MIT
#
# 表示例: (☁|user@example.com:my-project)
#
# 使い方 (bash):
#   source /path/to/gcloud-ps1.sh
#   PS1='[\u@\h \W $(gcloud_ps1)]\$ '
#
# 使い方 (zsh):
#   source /path/to/gcloud-ps1.sh
#   PROMPT='$(gcloud_ps1) '$PROMPT
#
# 設定は GCLOUD_PS1_* の環境変数で行う。一覧は README.md を参照。
#
# コマンド:
#   gcloudon  [-g|--global]  表示を有効にする
#   gcloudoff [-g|--global]  表示を無効にする (-g は全シェル共通)
#
# gcloud コマンドは実行せず、構成ファイルを直接読む。細かい仕様は docs/spec.md を参照。

# ---------------------------------------------------------------------------
# 初期化
# ---------------------------------------------------------------------------

# グローバル変数は関数の外で先に宣言する (zsh の WARN_CREATE_GLOBAL 対策)
_GCLOUD_PS1_SHELL=""
_GCLOUD_PS1_FG_RESET=""
_GCLOUD_PS1_BG_RESET=""
_GCLOUD_PS1_R=""
_GCLOUD_PS1_OUT=""
_GCLOUD_PS1_CONFIG=""
_GCLOUD_PS1_ACCOUNT=""
_GCLOUD_PS1_PROJECT=""
_GCLOUD_PS1_IMPERSONATE=""

_gcloud_ps1_init() {
	if [[ -n "${ZSH_VERSION-}" ]]; then
		_GCLOUD_PS1_SHELL="zsh"
		_GCLOUD_PS1_FG_RESET='%f'
		_GCLOUD_PS1_BG_RESET='%k'
		setopt PROMPT_SUBST
	elif [[ -n "${BASH_VERSION-}" ]]; then
		_GCLOUD_PS1_SHELL="bash"
		# readline に幅 0 と伝えるため \001 \002 で囲む
		_GCLOUD_PS1_FG_RESET=$'\001\033[39m\002'
		_GCLOUD_PS1_BG_RESET=$'\001\033[49m\002'
	else
		echo "gcloud-ps1: bash か zsh でのみ動作します" >&2
		return 1
	fi
}

# ---------------------------------------------------------------------------
# ヘルパー
# 結果は標準出力ではなく _GCLOUD_PS1_R に入れる (サブシェルを作らないため)。
# ---------------------------------------------------------------------------

# 色名 / 数値を 0-255 の番号にする。不明なら空文字。
_gcloud_ps1_color_code() {
	_GCLOUD_PS1_R=""
	case "${1-}" in
	black) _GCLOUD_PS1_R=0 ;;
	red) _GCLOUD_PS1_R=1 ;;
	green) _GCLOUD_PS1_R=2 ;;
	yellow) _GCLOUD_PS1_R=3 ;;
	blue) _GCLOUD_PS1_R=4 ;;
	magenta) _GCLOUD_PS1_R=5 ;;
	cyan) _GCLOUD_PS1_R=6 ;;
	white) _GCLOUD_PS1_R=7 ;;
	'' | *[!0-9]* | ????*) ;;
	*)
		# 先頭の 0 を 8 進数と解釈させない
		if ((10#$1 <= 255)); then
			_GCLOUD_PS1_R=$((10#$1))
		fi
		;;
	esac
	return 0
}

# 前景色 / 背景色の開始シーケンス。$1: fg|bg  $2: 色
_gcloud_ps1_color_open() {
	local layer="$1" code
	_gcloud_ps1_color_code "${2-}"
	code="$_GCLOUD_PS1_R"
	_GCLOUD_PS1_R=""
	[[ -z "$code" ]] && return 0

	if [[ "$_GCLOUD_PS1_SHELL" == "zsh" ]]; then
		if [[ "$layer" == "fg" ]]; then
			_GCLOUD_PS1_R="%F{${code}}"
		else
			_GCLOUD_PS1_R="%K{${code}}"
		fi
	else
		if [[ "$layer" == "fg" ]]; then
			_GCLOUD_PS1_R=$'\001\033[38;5;'"${code}"$'m\002'
		else
			_GCLOUD_PS1_R=$'\001\033[48;5;'"${code}"$'m\002'
		fi
	fi
	return 0
}

# _GCLOUD_PS1_OUT に色付きで文字列を追加する。$1: 色  $2: 文字列
_gcloud_ps1_paint() {
	_gcloud_ps1_color_open fg "${1-}"
	if [[ -z "$_GCLOUD_PS1_R" ]]; then
		_GCLOUD_PS1_OUT+="${2-}"
	else
		_GCLOUD_PS1_OUT+="${_GCLOUD_PS1_R}${2-}${_GCLOUD_PS1_FG_RESET}"
	fi
	return 0
}

# 長すぎる値を切り詰め、制御文字を除去し、zsh では % をエスケープする
# (プロンプト注入対策)。$1: 値
# LC_ALL に存在しないロケールが入っていると、bash は local の復元時に警告を出す。
# プロンプトのたびに表示されないよう、呼び出し側で標準エラー出力を捨てること。
_gcloud_ps1_sanitize() {
	_GCLOUD_PS1_R="${1-}"
	if ((${#_GCLOUD_PS1_R} > 256)); then
		_GCLOUD_PS1_R="${_GCLOUD_PS1_R:0:255}…"
	fi
	# バイト単位で判定する (C ロケールでも UTF-8 表現の C1 制御文字 U+0080-U+009F を除く)
	local LC_ALL=C
	if [[ "$_GCLOUD_PS1_SHELL" == "zsh" ]]; then
		# zsh は LC_ALL ではなく MULTIBYTE オプションで文字/バイトが決まる
		setopt LOCAL_OPTIONS NO_MULTIBYTE
	fi
	_GCLOUD_PS1_R="${_GCLOUD_PS1_R//[[:cntrl:]]/}"
	_GCLOUD_PS1_R="${_GCLOUD_PS1_R//$'\xc2'[$'\x80'-$'\x9f']/}"
	if [[ "$_GCLOUD_PS1_SHELL" == "zsh" ]]; then
		_GCLOUD_PS1_R="${_GCLOUD_PS1_R//\%/%%}"
	fi
	return 0
}

# 定義済みのシェル関数を呼び、出力を結果にする。関数が未指定・未定義・失敗なら既定値。
# $1: 関数名  $2: 関数に渡す値  $3: 既定値
_gcloud_ps1_call_fn() {
	_GCLOUD_PS1_R="${3-}"
	if [[ -n "${1-}" ]] && typeset -f -- "$1" >/dev/null 2>&1; then
		local out
		if out="$("$1" "${2-}" 2>/dev/null)"; then
			_GCLOUD_PS1_R="$out"
		fi
	fi
	return 0
}

# ---------------------------------------------------------------------------
# gcloud 構成の読み取り (gcloud は起動しない)
# 結果: _GCLOUD_PS1_CONFIG / _ACCOUNT / _PROJECT / _IMPERSONATE
#
# 対応する INI の範囲: gcloud 自身が書く形式 (小文字のキー、`key = value` または
# `key: value`)。キーの大文字小文字の違い、%(...)s 補間、
# [DEFAULT] の継承、SDK インストール先の properties は扱わない。
# 継続行 (直前のキー行より深く字下げされた行) は読み飛ばす。
# ---------------------------------------------------------------------------

_gcloud_ps1_read_config() {
	local dir="${CLOUDSDK_CONFIG:-${HOME:+$HOME/.config/gcloud}}"
	local name="${CLOUDSDK_ACTIVE_CONFIG_NAME-}"
	local nofile=false stripped file line trimmed section="" key val rest
	local have_key=false key_indent=0 indent
	local nl=$'\n' cr=$'\r'

	_GCLOUD_PS1_ACCOUNT=""
	_GCLOUD_PS1_PROJECT=""
	_GCLOUD_PS1_IMPERSONATE=""

	if [[ -z "$dir" ]]; then
		nofile=true
	fi

	if [[ -z "$name" ]]; then
		# active_config は空白を削らず中身全体を gcloud と同じ規則で判定する。
		# 形式 ^[a-z][-a-z0-9]*$ に合わなければ default。NONE は「構成なし」を表す予約名。
		if [[ -n "$dir" && -f "$dir/active_config" && -r "$dir/active_config" ]]; then
			# read -d '' は NUL を見つけたときだけ成功を返す (通常は EOF で非 0)。
			# NUL を含む名前は不正なので default にする。
			if IFS= read -r -d '' name <"$dir/active_config"; then
				name="default"
			fi
			# gcloud はテキストモードで読むので CRLF / CR は LF になる
			# (zsh は置換側の $'..' をクォート内で展開しないので変数を使う)
			name="${name//"$cr$nl"/$nl}"
			name="${name//"$cr"/$nl}"
			stripped="${name%$'\n'}"
			if [[ -z "$stripped" ]]; then
				name="default"
			elif [[ "$name" != "NONE" ]]; then
				case "$stripped" in
				[!a-z]* | *[!a-z0-9-]*) name="default" ;;
				esac
			fi
		fi
		name="${name:-default}"
	else
		# 環境変数の構成名は gcloud と同じく形式を検証しない (パス区切りだけは拒否)
		case "$name" in
		*/*) nofile=true ;;
		esac
	fi
	# 末尾に改行が付いた名前は、その名前のままファイルを探すため存在しない扱いになる
	if [[ "$name" == "NONE" || "$name" == *$'\n' ]]; then
		nofile=true
	fi
	_GCLOUD_PS1_CONFIG="${name%$'\n'}"

	file="$dir/configurations/config_${name}"
	if [[ "$nofile" == false && -f "$file" && -r "$file" ]]; then
		while IFS= read -r line || [[ -n "$line" ]]; do
			line="${line%"${line##*[![:space:]]}"}"
			trimmed="${line#"${line%%[![:space:]]*}"}"
			case "$trimmed" in
			'' | '#'* | ';'*) continue ;;
			esac

			# 直前のキー行より深い字下げは継続行 (configparser と同じ扱い)
			indent=$((${#line} - ${#trimmed}))
			if [[ "$have_key" == true ]] && ((indent > key_indent)); then
				continue
			fi

			case "$trimmed" in
			'['*)
				# 見出しの後ろにコメントがあってもよい ([core] # x)
				rest="${trimmed#\[}"
				section="${rest%\]*}"
				have_key=false
				continue
				;;
			esac
			# 区切りは最初に現れる = か : (configparser と同じ)
			[[ "$trimmed" == *[=:]* ]] || continue

			key="${trimmed%%[=:]*}"
			val="${trimmed#"$key"?}"
			key="${key%"${key##*[![:space:]]}"}"
			val="${val#"${val%%[![:space:]]*}"}"
			have_key=true
			key_indent=$indent

			case "${section}.${key}" in
			core.account) _GCLOUD_PS1_ACCOUNT="$val" ;;
			core.project) _GCLOUD_PS1_PROJECT="$val" ;;
			auth.impersonate_service_account) _GCLOUD_PS1_IMPERSONATE="$val" ;;
			esac
		done <"$file"
	fi

	# 環境変数は定義されていれば (空文字でも) 構成ファイルより優先される
	if [[ -n "${CLOUDSDK_CORE_ACCOUNT+x}" ]]; then
		_GCLOUD_PS1_ACCOUNT="$CLOUDSDK_CORE_ACCOUNT"
	fi
	if [[ -n "${CLOUDSDK_CORE_PROJECT+x}" ]]; then
		_GCLOUD_PS1_PROJECT="$CLOUDSDK_CORE_PROJECT"
	fi
	if [[ -n "${CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT+x}" ]]; then
		_GCLOUD_PS1_IMPERSONATE="$CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT"
	fi
	return 0
}

# ---------------------------------------------------------------------------
# 有効 / 無効の切り替え
# ---------------------------------------------------------------------------

# 全体設定のファイル。基準ディレクトリが決まらなければ空文字。
_gcloud_ps1_disabled_file() {
	local base="${XDG_CONFIG_HOME:-${HOME:+$HOME/.config}}"
	_GCLOUD_PS1_R=""
	if [[ -n "$base" ]]; then
		_GCLOUD_PS1_R="$base/gcloud-ps1/disabled"
	fi
	return 0
}

_gcloud_ps1_is_enabled() {
	case "${GCLOUD_PS1_ENABLED-}" in
	off) return 1 ;;
	on) return 0 ;;
	esac
	_gcloud_ps1_disabled_file
	if [[ -n "$_GCLOUD_PS1_R" && -e "$_GCLOUD_PS1_R" ]]; then
		return 1
	fi
	return 0
}

# $1: on|off  $2: オプション
_gcloud_ps1_toggle() {
	local state="$1" arg="${2-}" file

	case "$arg" in
	-h | --help)
		echo "usage: gcloud${state} [-g|--global]"
		return 0
		;;
	-g | --global)
		_gcloud_ps1_disabled_file
		file="$_GCLOUD_PS1_R"
		if [[ -z "$file" ]]; then
			echo "gcloud-ps1: HOME も XDG_CONFIG_HOME も未設定のため -g は使えません" >&2
			return 1
		fi
		if [[ "$state" == "off" ]]; then
			if ! { mkdir -p "${file%/*}" && : >"$file"; }; then
				echo "gcloud-ps1: $file を作成できません" >&2
				return 1
			fi
		else
			if ! rm -f "$file"; then
				echo "gcloud-ps1: $file を削除できません" >&2
				return 1
			fi
		fi
		unset GCLOUD_PS1_ENABLED
		;;
	'')
		GCLOUD_PS1_ENABLED="$state"
		;;
	*)
		echo "gcloud-ps1: 不明なオプション: $arg" >&2
		return 1
		;;
	esac
}

gcloudon() { _gcloud_ps1_toggle on "${1-}"; }
gcloudoff() { _gcloud_ps1_toggle off "${1-}"; }

# ---------------------------------------------------------------------------
# プロンプト本体
# ---------------------------------------------------------------------------

gcloud_ps1() {
	# 直前のコマンドの終了コードを保つ (PS1 の後ろで $? を使えるようにする)
	local rc=$?
	_gcloud_ps1_is_enabled || return "$rc"
	_gcloud_ps1_read_config

	local account_raw="$_GCLOUD_PS1_ACCOUNT"
	local project_raw="$_GCLOUD_PS1_PROJECT"
	local imp_raw="$_GCLOUD_PS1_IMPERSONATE"
	local config="$_GCLOUD_PS1_CONFIG"
	local na="${GCLOUD_PS1_NA-N/A}"

	if [[ "${GCLOUD_PS1_HIDE_IF_NOCONFIG:-false}" == "true" &&
		-z "$account_raw" && -z "$project_raw" && -z "$imp_raw" ]]; then
		return "$rc"
	fi

	local account project
	if [[ -z "$account_raw" ]]; then
		account="$na"
	else
		case "${GCLOUD_PS1_ACCOUNT_MODE-full}" in
		user) account="${account_raw%%@*}" ;;
		domain)
			if [[ "$account_raw" == *@* ]]; then
				account="${account_raw#*@}"
			else
				account=""
			fi
			;;
		*) account="$account_raw" ;;
		esac
		account="${account:-$na}"
	fi
	project="${project_raw:-$na}"

	local body=false color symbol bg

	_GCLOUD_PS1_OUT=""
	_gcloud_ps1_color_open bg "${GCLOUD_PS1_BG_COLOR-}"
	bg="$_GCLOUD_PS1_R"
	_GCLOUD_PS1_OUT+="$bg"

	_gcloud_ps1_paint "${GCLOUD_PS1_PREFIX_COLOR-}" "${GCLOUD_PS1_PREFIX-(}"

	if [[ "${GCLOUD_PS1_SYMBOL_ENABLE:-true}" == "true" ]]; then
		symbol="${GCLOUD_PS1_SYMBOL_CUSTOM-☁}"
		[[ "${GCLOUD_PS1_SYMBOL_PADDING:-false}" == "true" ]] && symbol+=" "
		_gcloud_ps1_paint "${GCLOUD_PS1_SYMBOL_COLOR-blue}" "$symbol"
		_gcloud_ps1_paint "${GCLOUD_PS1_SEPARATOR_COLOR-}" "${GCLOUD_PS1_SEPARATOR-|}"
	fi

	if [[ "${GCLOUD_PS1_CONFIG_ENABLE:-false}" == "true" ]]; then
		_gcloud_ps1_sanitize "$config" 2>/dev/null
		_gcloud_ps1_paint "${GCLOUD_PS1_CONFIG_COLOR-yellow}" "$_GCLOUD_PS1_R"
		body=true
	fi

	if [[ "${GCLOUD_PS1_ACCOUNT_ENABLE:-true}" == "true" ]]; then
		[[ "$body" == true ]] && _gcloud_ps1_paint "${GCLOUD_PS1_DIVIDER_COLOR-}" "${GCLOUD_PS1_DIVIDER-:}"
		_gcloud_ps1_call_fn "${GCLOUD_PS1_ACCOUNT_COLOR_FUNCTION-}" "$account_raw" \
			"${GCLOUD_PS1_ACCOUNT_COLOR-red}"
		color="$_GCLOUD_PS1_R"
		_gcloud_ps1_call_fn "${GCLOUD_PS1_ACCOUNT_FUNCTION-}" "$account" "$account"
		_gcloud_ps1_sanitize "$_GCLOUD_PS1_R" 2>/dev/null
		_gcloud_ps1_paint "$color" "$_GCLOUD_PS1_R"
		body=true
	fi

	if [[ -n "$imp_raw" && "${GCLOUD_PS1_IMPERSONATE_ENABLE:-true}" == "true" ]]; then
		color="${GCLOUD_PS1_IMPERSONATE_COLOR-magenta}"
		if [[ "${GCLOUD_PS1_ACCOUNT_ENABLE:-true}" == "true" ]]; then
			_gcloud_ps1_paint "$color" "${GCLOUD_PS1_IMPERSONATE_ARROW-→}"
		elif [[ "$body" == true ]]; then
			_gcloud_ps1_paint "${GCLOUD_PS1_DIVIDER_COLOR-}" "${GCLOUD_PS1_DIVIDER-:}"
		fi
		_gcloud_ps1_sanitize "$imp_raw" 2>/dev/null
		_gcloud_ps1_paint "$color" "$_GCLOUD_PS1_R"
		body=true
	fi

	if [[ "${GCLOUD_PS1_PROJECT_ENABLE:-true}" == "true" ]]; then
		[[ "$body" == true ]] && _gcloud_ps1_paint "${GCLOUD_PS1_DIVIDER_COLOR-}" "${GCLOUD_PS1_DIVIDER-:}"
		_gcloud_ps1_call_fn "${GCLOUD_PS1_PROJECT_COLOR_FUNCTION-}" "$project_raw" \
			"${GCLOUD_PS1_PROJECT_COLOR-cyan}"
		color="$_GCLOUD_PS1_R"
		_gcloud_ps1_call_fn "${GCLOUD_PS1_PROJECT_FUNCTION-}" "$project" "$project"
		_gcloud_ps1_sanitize "$_GCLOUD_PS1_R" 2>/dev/null
		_gcloud_ps1_paint "$color" "$_GCLOUD_PS1_R"
	fi

	_gcloud_ps1_paint "${GCLOUD_PS1_SUFFIX_COLOR-}" "${GCLOUD_PS1_SUFFIX-)}"
	[[ -n "$bg" ]] && _GCLOUD_PS1_OUT+="$_GCLOUD_PS1_BG_RESET"

	printf '%s' "$_GCLOUD_PS1_OUT"
	return "$rc"
}

_gcloud_ps1_init
