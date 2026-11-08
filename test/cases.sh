#!/usr/bin/env bash
# gcloud-ps1 のテストケース。bash / zsh のどちらでも実行できる。
# 直接ではなく test/run.sh から使う。必要な環境変数:
#   GCLOUD_PS1_SRC  gcloud-ps1.sh のパス
#   FIXTURE_DIR     構成ファイルを置く作業用ディレクトリ (CLOUDSDK_CONFIG になる)

# shellcheck disable=SC1090,SC2016

# GCLOUD_PS1_* は消すので、受け取った値を先に退避する
src="$GCLOUD_PS1_SRC"

# 作業用ディレクトリが無いと、実際の gcloud の設定を読み書きしてしまう
if [ -z "${FIXTURE_DIR-}" ] || [ ! -d "$FIXTURE_DIR" ]; then
	echo "FIXTURE_DIR が空か、ディレクトリではありません" >&2
	exit 1
fi

# 利用者が .bashrc などで設定している値の影響を受けないよう、先に全部消す
for v in $(env | sed -n 's/^\(GCLOUD_PS1_[A-Za-z_]*\)=.*/\1/p'); do
	unset "$v"
done
unset CLOUDSDK_ACTIVE_CONFIG_NAME CLOUDSDK_CORE_ACCOUNT CLOUDSDK_CORE_PROJECT \
	CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT

. "$src"

export CLOUDSDK_CONFIG="$FIXTURE_DIR"
export XDG_CONFIG_HOME="$FIXTURE_DIR/xdg"

# 比較しやすいように、記号と色を無効にしておく
export GCLOUD_PS1_SYMBOL_ENABLE=false
export GCLOUD_PS1_SYMBOL_COLOR='' GCLOUD_PS1_CONFIG_COLOR='' GCLOUD_PS1_ACCOUNT_COLOR=''
export GCLOUD_PS1_PROJECT_COLOR='' GCLOUD_PS1_IMPERSONATE_COLOR=''
export GCLOUD_PS1_IMPERSONATE_ENABLE=false

CONF="$FIXTURE_DIR/configurations"
mkdir -p "$CONF" "$XDG_CONFIG_HOME"

write() { printf '%s' "$2" >"$CONF/config_$1"; }
set_active() { printf '%b' "$1" >"$FIXTURE_DIR/active_config"; }

write default $'[core]\naccount = me@example.com\nproject = proj-default\n[compute]\nproject = wrong\n[auth]\nimpersonate_service_account = sa@proj.iam.gserviceaccount.com\n'
write dev $'[core]\naccount = dev@example.org\nproject = proj-dev\n'
write Foo $'[core]\nproject = upper-foo\n'
write comment $'[core] # comment\naccount = c@example.com\n[compute] ; other\nproject = wrong\n[core]\nproject = proj-comment\n'
write indent $'[core]\n  account = i@example.com\n  project = proj-indent\n'
write cont $'[core]\naccount = k@example.com\nproject = first\n  continued\n'
write colon $'[core]\nproject: proj-colon\naccount = a:b@example.com\n'
write coloncont $'[core]\nfoo: 1\n  project = hidden\n'
write eq $'[core]\nproject = a=b=c\n'
write crlf $'[core]\r\naccount = w@example.com\r\nproject = proj-crlf\r\n'

fail=0
count=0

# t 名前 期待値 実行するコマンド
t() {
	local got
	count=$((count + 1))
	got="$(eval "$3" 2>&1)"
	if [ "$got" = "$2" ]; then
		echo "ok   $1"
	else
		echo "FAIL $1"
		echo "     期待: [$2]"
		echo "     実際: [$got]"
		fail=$((fail + 1))
	fi
}

set_active default
t "既定の構成" "(me@example.com:proj-default)" 'gcloud_ps1'
t "他セクションの値は拾わない" "(me@example.com:proj-default)" 'gcloud_ps1'
t "構成名を表示" "(default:me@example.com:proj-default)" 'GCLOUD_PS1_CONFIG_ENABLE=true gcloud_ps1'
t "アカウント user" "(me:proj-default)" 'GCLOUD_PS1_ACCOUNT_MODE=user gcloud_ps1'
t "アカウント domain" "(example.com:proj-default)" 'GCLOUD_PS1_ACCOUNT_MODE=domain gcloud_ps1'
t "プロジェクトのみ" "(proj-default)" 'GCLOUD_PS1_ACCOUNT_ENABLE=false gcloud_ps1'
t "記号と区切り" "(X>me@example.com:proj-default)" 'GCLOUD_PS1_SYMBOL_ENABLE=true GCLOUD_PS1_SYMBOL_CUSTOM=X GCLOUD_PS1_SEPARATOR=">" gcloud_ps1'
t "区切り・括弧の変更" "[me@example.com/proj-default]" 'GCLOUD_PS1_PREFIX="[" GCLOUD_PS1_SUFFIX="]" GCLOUD_PS1_DIVIDER="/" gcloud_ps1'
t "impersonate 表示" "(me@example.com→sa@proj.iam.gserviceaccount.com:proj-default)" 'GCLOUD_PS1_IMPERSONATE_ENABLE=true gcloud_ps1'
t "impersonate の矢印変更" "(me@example.com>sa@proj.iam.gserviceaccount.com:proj-default)" 'GCLOUD_PS1_IMPERSONATE_ENABLE=true GCLOUD_PS1_IMPERSONATE_ARROW=">" gcloud_ps1'

# 構成の選択
t "環境変数で構成を指定" "(dev@example.org:proj-dev)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=dev gcloud_ps1'
t "環境変数の構成名は大文字も可" "(N/A:upper-foo)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=Foo gcloud_ps1'
t "存在しない構成は N/A" "(N/A:N/A)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=nosuch gcloud_ps1'
t "構成名の / は拒否" "(N/A:N/A)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=../x gcloud_ps1'
t "NONE は N/A" "(N/A:N/A)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=NONE gcloud_ps1'
set_active dev
t "active_config を読む" "(dev@example.org:proj-dev)" 'gcloud_ps1'
set_active 'dev  '
t "active_config の空白は不正で default" "(me@example.com:proj-default)" 'gcloud_ps1'
set_active 'dev\n'
t "active_config の末尾改行は N/A" "(N/A:N/A)" 'gcloud_ps1'
set_active 'dev\r\n'
t "active_config の CRLF は N/A" "(N/A:N/A)" 'gcloud_ps1'
set_active 'Dev'
t "active_config の不正な名前は default" "(me@example.com:proj-default)" 'gcloud_ps1'
set_active 'dev\0x'
t "active_config の NUL は default" "(me@example.com:proj-default)" 'gcloud_ps1'
set_active ''
t "active_config が空なら default" "(me@example.com:proj-default)" 'gcloud_ps1'
set_active 'NONE'
t "active_config が NONE" "(N/A:N/A)" 'gcloud_ps1'
set_active 'NONE\n'
t "active_config が NONE+改行は default" "(me@example.com:proj-default)" 'gcloud_ps1'
set_active default

# 構成ファイルの読み取り
t "見出し行のコメント" "(c@example.com:proj-comment)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=comment gcloud_ps1'
t "字下げしたキー" "(i@example.com:proj-indent)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=indent gcloud_ps1'
t "継続行は読み飛ばす" "(k@example.com:first)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=cont gcloud_ps1'
t ": 区切りと値中の :" "(a:b@example.com:proj-colon)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=colon gcloud_ps1'
t ": 区切りのキーの継続行" "(N/A:N/A)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=coloncont gcloud_ps1'
t "値中の =" "(N/A:a=b=c)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=eq gcloud_ps1'
t "CRLF の構成ファイル" "(w@example.com:proj-crlf)" 'CLOUDSDK_ACTIVE_CONFIG_NAME=crlf gcloud_ps1'

# 環境変数による上書き
t "CLOUDSDK_CORE_PROJECT" "(me@example.com:envproj)" 'CLOUDSDK_CORE_PROJECT=envproj gcloud_ps1'
t "CLOUDSDK_CORE_ACCOUNT" "(env@example.com:proj-default)" 'CLOUDSDK_CORE_ACCOUNT=env@example.com gcloud_ps1'
t "空の CLOUDSDK_CORE_PROJECT" "(me@example.com:N/A)" 'CLOUDSDK_CORE_PROJECT= gcloud_ps1'
t "環境変数の impersonate" "(me@example.com→env-sa:proj-default)" 'GCLOUD_PS1_IMPERSONATE_ENABLE=true CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=env-sa gcloud_ps1'
t "N/A の文言を変更" "(me@example.com:-)" 'CLOUDSDK_CORE_PROJECT= GCLOUD_PS1_NA="-" gcloud_ps1'

# 非表示
t "値が無ければ非表示" "" 'CLOUDSDK_CONFIG=/nonexistent GCLOUD_PS1_HIDE_IF_NOCONFIG=true gcloud_ps1'
t "gcloudoff" "" 'gcloudoff; gcloud_ps1'
t "gcloudon" "(me@example.com:proj-default)" 'gcloudoff; gcloudon; gcloud_ps1'
t "gcloudoff -g" "" 'gcloudoff -g; gcloud_ps1'
t "gcloudon で全体設定を上書き" "(me@example.com:proj-default)" 'gcloudoff -g; gcloudon; gcloud_ps1'
t "gcloudon -g" "(me@example.com:proj-default)" 'gcloudoff -g; gcloudon -g; gcloud_ps1'
t "gcloudoff -g はファイルで効く (環境変数を解除しても非表示)" "" 'gcloudoff -g; unset GCLOUD_PS1_ENABLED; gcloud_ps1'
t "gcloudoff -g で無効化ファイルができる" "yes" 'gcloudoff -g; [ -e "$XDG_CONFIG_HOME/gcloud-ps1/disabled" ] && echo yes'
t "gcloudon -g で無効化ファイルが消える (環境変数を解除しても表示)" "(me@example.com:proj-default)" 'gcloudoff -g; gcloudon -g; unset GCLOUD_PS1_ENABLED; gcloud_ps1'
t "gcloudon -g のあと無効化ファイルは無い" "no" 'gcloudoff -g; gcloudon -g; [ -e "$XDG_CONFIG_HOME/gcloud-ps1/disabled" ] && echo yes || echo no'
t "不明なオプションは失敗" "1" 'gcloudoff --nosuch >/dev/null 2>&1; echo $?'

# 加工関数・色関数
upper_project() { printf '%s' "${1}-X"; }
fail_project() { return 1; }
t "加工関数" "(me@example.com:proj-default-X)" 'GCLOUD_PS1_PROJECT_FUNCTION=upper_project gcloud_ps1'
t "失敗した加工関数は元の値" "(me@example.com:proj-default)" 'GCLOUD_PS1_PROJECT_FUNCTION=fail_project gcloud_ps1'
t "未定義の関数名は無視" "(me@example.com:proj-default)" 'GCLOUD_PS1_PROJECT_FUNCTION=nosuchfunc gcloud_ps1'
t "-p は関数名として扱わない" "(me@example.com:proj-default)" 'GCLOUD_PS1_PROJECT_FUNCTION=-p gcloud_ps1'

# 色 (エスケープシーケンスまで含めて完全一致で比べる)
# fg N: 前景色 N の開始シーケンス  rst: 前景色のリセット
if [ -n "${ZSH_VERSION-}" ]; then
	fg() { printf '%%F{%s}' "$1"; }
	rst='%f'
else
	fg() { printf '\001\033[38;5;%sm\002' "$1"; }
	rst=$'\001\033[39m\002'
fi
color_fn() { echo red; }
t "色関数の戻り値が使われる" "(me@example.com:$(fg 1)proj-default${rst})" 'GCLOUD_PS1_PROJECT_COLOR_FUNCTION=color_fn gcloud_ps1'
t "色名で指定" "(me@example.com:$(fg 2)proj-default${rst})" 'GCLOUD_PS1_PROJECT_COLOR=green gcloud_ps1'
t "色を数値で指定" "(me@example.com:$(fg 208)proj-default${rst})" 'GCLOUD_PS1_PROJECT_COLOR=208 gcloud_ps1'
t "先頭 0 の色 (08) は 8 進数にしない" "(me@example.com:$(fg 8)proj-default${rst})" 'GCLOUD_PS1_PROJECT_COLOR=08 gcloud_ps1'
t "不正な色は色なし" "(me@example.com:proj-default)" 'GCLOUD_PS1_PROJECT_COLOR=nosuch gcloud_ps1'
t "範囲外の色は色なし" "(me@example.com:proj-default)" 'GCLOUD_PS1_PROJECT_COLOR=256 gcloud_ps1'
t "DIVIDER_COLOR" "(me@example.com$(fg 3):${rst}proj-default)" 'GCLOUD_PS1_DIVIDER_COLOR=yellow gcloud_ps1'
t "SEPARATOR_COLOR" "(X$(fg 2)|${rst}me@example.com:proj-default)" 'GCLOUD_PS1_SYMBOL_ENABLE=true GCLOUD_PS1_SYMBOL_CUSTOM=X GCLOUD_PS1_SEPARATOR_COLOR=green gcloud_ps1'
t "PREFIX_COLOR / SUFFIX_COLOR" "$(fg 3)(${rst}me@example.com:proj-default$(fg 4))${rst}" 'GCLOUD_PS1_PREFIX_COLOR=yellow GCLOUD_PS1_SUFFIX_COLOR=blue gcloud_ps1'

# 値のサニタイズ
t "制御文字を除去 (ESC SOH CR)" "(me@example.com:a[2Jb)" "CLOUDSDK_CORE_PROJECT=\$'a\\e[2J\\x01\\rb' gcloud_ps1"
t "C1 制御文字を除去" "(me@example.com:ab)" "CLOUDSDK_CORE_PROJECT=\$'a\\xc2\\x9bb' gcloud_ps1"
t "日本語は保持" "(me@example.com:日本語)" "CLOUDSDK_CORE_PROJECT='日本語' gcloud_ps1"
long=$(printf 'x%.0s' $(seq 1 300))
short=$(printf 'x%.0s' $(seq 1 255))
t "256 文字を超えたら 255 文字 + … に切り詰め" "(me@example.com:${short}…)" "CLOUDSDK_CORE_PROJECT=$long gcloud_ps1"
exact=$(printf 'x%.0s' $(seq 1 256))
t "256 文字ちょうどは切り詰めない" "(me@example.com:${exact})" "CLOUDSDK_CORE_PROJECT=$exact gcloud_ps1"
if [ -n "${ZSH_VERSION-}" ]; then
	t "zsh: % をエスケープ" "(me@example.com:a%%n)" "CLOUDSDK_CORE_PROJECT='a%n' gcloud_ps1"
else
	t "bash: % はそのまま" "(me@example.com:a%n)" "CLOUDSDK_CORE_PROJECT='a%n' gcloud_ps1"
fi

echo
echo "$count 件中 $((count - fail)) 件成功"
[ "$fail" -eq 0 ]
