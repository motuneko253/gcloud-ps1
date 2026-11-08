#!/usr/bin/env bash
# gcloud-ps1 のテストを実行する。
#
#   test/run.sh                 bash と(あれば)zsh で実行
#   GCLOUD_PS1_TEST_SHELLS="bash /path/to/zsh" test/run.sh
#                               使うシェルを明示する(空白区切り)
#
# 構成ファイルは一時ディレクトリに作るので、実際の gcloud の設定には触れない。

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/../gcloud-ps1.sh"

shells="${GCLOUD_PS1_TEST_SHELLS:-}"
if [ -z "$shells" ]; then
	shells="bash"
	if command -v zsh >/dev/null 2>&1; then
		shells="$shells zsh"
	fi
fi

status=0
for sh in $shells; do
	if ! command -v "$sh" >/dev/null 2>&1 && [ ! -x "$sh" ]; then
		echo "シェルが見つかりません: $sh" >&2
		status=1
		continue
	fi

	if ! fixture="$(mktemp -d "${TMPDIR:-/tmp}/gcloud-ps1-test.XXXXXX")" || [ ! -d "$fixture" ]; then
		echo "一時ディレクトリを作成できません" >&2
		status=1
		continue
	fi
	trap 'rm -rf "$fixture"' EXIT

	opts=()
	case "$(basename "$sh")" in
	zsh) opts=(-f) ;;
	esac

	echo "===== $sh ====="
	if ! GCLOUD_PS1_SRC="$src" FIXTURE_DIR="$fixture" "$sh" "${opts[@]+"${opts[@]}"}" "$here/cases.sh"; then
		status=1
	fi
	rm -rf "$fixture"
	trap - EXIT
	echo
done

if [ "$status" -eq 0 ]; then
	echo "すべて成功"
else
	echo "失敗あり" >&2
fi
exit "$status"
