#!/usr/bin/env bash
# gcloud-ps1: gcloud のアクティブな構成(アカウント / プロジェクト)をプロンプトに表示する
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
# gcloud コマンドは実行せず、構成ファイルを直接読む。*_FUNCTION / *_COLOR_FUNCTION を
# 使わない限り関数の内部ではサブシェルを作らないので、プロンプト 1 回あたりの fork は
# $(gcloud_ps1) の 1 回だけ (コールバックは 1 つにつき 1 回 fork する)。
#
# 値の解決順 (gcloud 本体と同じ):
#   アカウント : CLOUDSDK_CORE_ACCOUNT > 構成の core/account
#   プロジェクト: CLOUDSDK_CORE_PROJECT > 構成の core/project
#   impersonate: CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT > 構成の auth/impersonate_service_account
#   構成名     : CLOUDSDK_ACTIVE_CONFIG_NAME > $CLOUDSDK_CONFIG/active_config > default
#   (アカウント等の環境変数は「定義されているか」で判定する。空文字でも構成ファイルより優先され、
#    N/A 表示になる。構成名の環境変数は gcloud と同じく形式を検証せず、そのまま config_<名前> を
#    読む。active_config ファイルの中身が ^[a-z][-a-z0-9]*$ に合わなければ default とみなす)
#
# 設定用の環境変数 (すべて任意。source の前後どちらで設定してもよい。()内は既定値):
#   GCLOUD_PS1_SYMBOL_ENABLE      記号を表示する                          (true)
#   GCLOUD_PS1_SYMBOL_PADDING     記号の後ろに空白を足す                  (false)
#   GCLOUD_PS1_SYMBOL_CUSTOM      表示する記号                            (☁)
#   GCLOUD_PS1_CONFIG_ENABLE      構成名を表示する                        (false)
#   GCLOUD_PS1_ACCOUNT_ENABLE     アカウントを表示する                    (true)
#   GCLOUD_PS1_PROJECT_ENABLE     プロジェクトを表示する                  (true)
#   GCLOUD_PS1_IMPERSONATE_ENABLE impersonate 中のサービスアカウントを表示 (true)
#   GCLOUD_PS1_ACCOUNT_MODE       full | user(@より前) | domain(@より後)    (full)
#   GCLOUD_PS1_NA                 値が無いときの表示                      (N/A)
#   GCLOUD_PS1_PREFIX / SEPARATOR / DIVIDER / SUFFIX                        (( | : ))
#   GCLOUD_PS1_IMPERSONATE_ARROW  アカウントと impersonate 先の間         (→)
#   GCLOUD_PS1_SYMBOL_COLOR       記号の色                                (blue)
#   GCLOUD_PS1_CONFIG_COLOR       構成名の色                              (yellow)
#   GCLOUD_PS1_ACCOUNT_COLOR      アカウントの色                          (red)
#   GCLOUD_PS1_PROJECT_COLOR      プロジェクトの色                        (cyan)
#   GCLOUD_PS1_IMPERSONATE_COLOR  impersonate 先の色                      (magenta)
#   GCLOUD_PS1_DIVIDER_COLOR      DIVIDER (アカウントとプロジェクトの間など) の色 (なし)
#   GCLOUD_PS1_SEPARATOR_COLOR    SEPARATOR (記号と本体の間) の色          (なし)
#   GCLOUD_PS1_PREFIX_COLOR / SUFFIX_COLOR / BG_COLOR                       (なし)
#   GCLOUD_PS1_HIDE_IF_NOCONFIG   アカウント・プロジェクト・impersonate のいずれも無ければ非表示 (false)
#   GCLOUD_PS1_ACCOUNT_FUNCTION   アカウント表示を加工する関数 (引数: 値、出力: 表示)
#   GCLOUD_PS1_PROJECT_FUNCTION   プロジェクト表示を加工する関数 (同上)
#   GCLOUD_PS1_ACCOUNT_COLOR_FUNCTION  アカウントの色を返す関数 (引数: 値、出力: 色)
#   GCLOUD_PS1_PROJECT_COLOR_FUNCTION  プロジェクトの色を返す関数 (同上)
#
# *_FUNCTION は「現在のシェルで定義済みのシェル関数」だけが呼ばれる。実行コードを
# 指定する設定なので、信頼できる関数だけを指定すること。失敗したときは元の値を使う。
#
# 色は black red green yellow blue magenta cyan white か 0-255 の数値で指定する。
# 空文字を指定すると色なしになる。
#
# コマンド:
#   gcloudon  [-g|--global]  表示を有効にする
#   gcloudoff [-g|--global]  表示を無効にする
#   -g を付けると全シェル共通 (${XDG_CONFIG_HOME:-$HOME/.config}/gcloud-ps1/disabled)。
#   -g なしの設定 (GCLOUD_PS1_ENABLED) は、そのシェルだけで全体設定より優先される。

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

# 指定した関数 (定義済みのシェル関数のみ) で値を加工する。失敗したら元の値。
# $1: 関数名  $2: 値
_gcloud_ps1_apply_fn() {
	_GCLOUD_PS1_R="${2-}"
	if [[ -n "${1-}" ]] && typeset -f -- "$1" >/dev/null 2>&1; then
		local out
		if out="$("$1" "${2-}" 2>/dev/null)"; then
			_GCLOUD_PS1_R="$out"
		fi
	fi
	return 0
}

# 色を決める。$1: 既定の色  $2: 色を返す関数名  $3: 値
_gcloud_ps1_resolve_color() {
	_GCLOUD_PS1_R="${1-}"
	if [[ -n "${2-}" ]] && typeset -f -- "$2" >/dev/null 2>&1; then
		local out
		if out="$("$2" "${3-}" 2>/dev/null)"; then
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
	_gcloud_ps1_is_enabled || return 0
	_gcloud_ps1_read_config

	local account_raw="$_GCLOUD_PS1_ACCOUNT"
	local project_raw="$_GCLOUD_PS1_PROJECT"
	local imp_raw="$_GCLOUD_PS1_IMPERSONATE"
	local config="$_GCLOUD_PS1_CONFIG"
	local na="${GCLOUD_PS1_NA-N/A}"

	if [[ "${GCLOUD_PS1_HIDE_IF_NOCONFIG:-false}" == "true" &&
		-z "$account_raw" && -z "$project_raw" && -z "$imp_raw" ]]; then
		return 0
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
				account="$na"
			fi
			;;
		*) account="$account_raw" ;;
		esac
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
		_gcloud_ps1_sanitize "$config"
		_gcloud_ps1_paint "${GCLOUD_PS1_CONFIG_COLOR-yellow}" "$_GCLOUD_PS1_R"
		body=true
	fi

	if [[ "${GCLOUD_PS1_ACCOUNT_ENABLE:-true}" == "true" ]]; then
		[[ "$body" == true ]] && _gcloud_ps1_paint "${GCLOUD_PS1_DIVIDER_COLOR-}" "${GCLOUD_PS1_DIVIDER-:}"
		_gcloud_ps1_resolve_color "${GCLOUD_PS1_ACCOUNT_COLOR-red}" \
			"${GCLOUD_PS1_ACCOUNT_COLOR_FUNCTION-}" "$account_raw"
		color="$_GCLOUD_PS1_R"
		_gcloud_ps1_apply_fn "${GCLOUD_PS1_ACCOUNT_FUNCTION-}" "$account"
		_gcloud_ps1_sanitize "$_GCLOUD_PS1_R"
		_gcloud_ps1_paint "$color" "$_GCLOUD_PS1_R"
		body=true
	fi

	if [[ -n "$imp_raw" && "${GCLOUD_PS1_IMPERSONATE_ENABLE:-true}" == "true" ]]; then
		[[ "$body" == true && "${GCLOUD_PS1_ACCOUNT_ENABLE:-true}" != "true" ]] &&
			_gcloud_ps1_paint "${GCLOUD_PS1_DIVIDER_COLOR-}" "${GCLOUD_PS1_DIVIDER-:}"
		color="${GCLOUD_PS1_IMPERSONATE_COLOR-magenta}"
		_gcloud_ps1_paint "$color" "${GCLOUD_PS1_IMPERSONATE_ARROW-→}"
		_gcloud_ps1_sanitize "$imp_raw"
		_gcloud_ps1_paint "$color" "$_GCLOUD_PS1_R"
		body=true
	fi

	if [[ "${GCLOUD_PS1_PROJECT_ENABLE:-true}" == "true" ]]; then
		[[ "$body" == true ]] && _gcloud_ps1_paint "${GCLOUD_PS1_DIVIDER_COLOR-}" "${GCLOUD_PS1_DIVIDER-:}"
		_gcloud_ps1_resolve_color "${GCLOUD_PS1_PROJECT_COLOR-cyan}" \
			"${GCLOUD_PS1_PROJECT_COLOR_FUNCTION-}" "$project_raw"
		color="$_GCLOUD_PS1_R"
		_gcloud_ps1_apply_fn "${GCLOUD_PS1_PROJECT_FUNCTION-}" "$project"
		_gcloud_ps1_sanitize "$_GCLOUD_PS1_R"
		_gcloud_ps1_paint "$color" "$_GCLOUD_PS1_R"
	fi

	_gcloud_ps1_paint "${GCLOUD_PS1_SUFFIX_COLOR-}" "${GCLOUD_PS1_SUFFIX-)}"
	[[ -n "$bg" ]] && _GCLOUD_PS1_OUT+="$_GCLOUD_PS1_BG_RESET"

	printf '%s' "$_GCLOUD_PS1_OUT"
}

_gcloud_ps1_init
