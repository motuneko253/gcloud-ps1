# gcloud-ps1

[![ci](https://github.com/motuneko253/gcloud-ps1/actions/workflows/ci.yml/badge.svg)](https://github.com/motuneko253/gcloud-ps1/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

今アクティブな gcloud の構成(アカウントとプロジェクト)を、bash / zsh のプロンプトに表示するスクリプトです。

![gcloud-ps1 の表示例](docs/demo.svg)

`gcloud` を実行する前に、どのアカウントとプロジェクトを向いているかをプロンプトで確認できます。

## 特徴

- `gcloud` コマンドを実行せず構成ファイルを直接読むので軽い(1 回あたり数ミリ秒)
- 構成を切り替えると、次のプロンプトですぐ反映される
- 色、区切り文字、表示する項目を環境変数で変更できる
- プロジェクト名に応じて色を変えられる(本番だけ赤にする、など)
- サービスアカウントを impersonate しているときは、それも表示する
- bash 3.2 以降と zsh で動く

## インストール

```bash
git clone https://github.com/motuneko253/gcloud-ps1.git ~/gcloud-ps1
```

bash は `~/.bashrc` に追記します。

```bash
source ~/gcloud-ps1/gcloud-ps1.sh
PS1='\u@\h:\w $(gcloud_ps1) \$ '
```

zsh は `~/.zshrc` に追記します。

```zsh
source ~/gcloud-ps1/gcloud-ps1.sh
PROMPT='$(gcloud_ps1) '$PROMPT
```

`$(gcloud_ps1)` を含む部分は、シングルクォートで書いてください。ダブルクォートだと代入時に 1 回だけ評価され、構成を切り替えても表示が変わりません。

更新は `git -C ~/gcloud-ps1 pull` です。

## 表示

```text
(☁|admin@example.com:my-project)
```

左から、記号、アカウント、プロジェクトです。値が無いときは `N/A` と表示します。

`auth/impersonate_service_account` を設定しているときは、アカウントの後ろにサービスアカウントを表示します。

```text
(☁|admin@example.com→deploy@my-project.iam.gserviceaccount.com:my-project)
```

表示のオン・オフは次のコマンドで切り替えます。

| コマンド | 動作 |
| --- | --- |
| `gcloudoff` | 今のシェルだけ非表示にする |
| `gcloudon` | 今のシェルだけ表示する |
| `gcloudoff -g` | すべてのシェルで非表示にする |
| `gcloudon -g` | すべてのシェルで表示に戻す |

## 設定

設定はすべて環境変数です。`source` の前後どちらで設定しても動きます。

### 表示する内容

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `GCLOUD_PS1_SYMBOL_ENABLE` | `true` | 記号を表示する |
| `GCLOUD_PS1_SYMBOL_CUSTOM` | `☁` | 記号 |
| `GCLOUD_PS1_SYMBOL_PADDING` | `false` | 記号の後ろに空白を入れる |
| `GCLOUD_PS1_CONFIG_ENABLE` | `false` | 構成名を表示する |
| `GCLOUD_PS1_ACCOUNT_ENABLE` | `true` | アカウントを表示する |
| `GCLOUD_PS1_ACCOUNT_MODE` | `full` | `full` は全体、`user` は `@` より前、`domain` は `@` より後 |
| `GCLOUD_PS1_PROJECT_ENABLE` | `true` | プロジェクトを表示する |
| `GCLOUD_PS1_IMPERSONATE_ENABLE` | `true` | impersonate 先を表示する |
| `GCLOUD_PS1_IMPERSONATE_ARROW` | `→` | アカウントと impersonate 先の間 |
| `GCLOUD_PS1_PREFIX` | `(` | 先頭の文字 |
| `GCLOUD_PS1_SUFFIX` | `)` | 末尾の文字 |
| `GCLOUD_PS1_SEPARATOR` | `\|` | 記号と本体の間 |
| `GCLOUD_PS1_DIVIDER` | `:` | 構成名・アカウント・プロジェクトの間 |
| `GCLOUD_PS1_NA` | `N/A` | 値が無いときの表示 |
| `GCLOUD_PS1_HIDE_IF_NOCONFIG` | `false` | アカウントもプロジェクトも無いときは何も表示しない |

### 色

色名(`black` `red` `green` `yellow` `blue` `magenta` `cyan` `white`)か、`0`〜`255` の数値で指定します。空文字にすると色なしです。

| 変数 | 既定値 | 対象 |
| --- | --- | --- |
| `GCLOUD_PS1_SYMBOL_COLOR` | `blue` | 記号 |
| `GCLOUD_PS1_CONFIG_COLOR` | `yellow` | 構成名 |
| `GCLOUD_PS1_ACCOUNT_COLOR` | `red` | アカウント |
| `GCLOUD_PS1_PROJECT_COLOR` | `cyan` | プロジェクト |
| `GCLOUD_PS1_IMPERSONATE_COLOR` | `magenta` | impersonate 先 |
| `GCLOUD_PS1_PREFIX_COLOR` / `GCLOUD_PS1_SUFFIX_COLOR` | なし | 括弧 |
| `GCLOUD_PS1_SEPARATOR_COLOR` / `GCLOUD_PS1_DIVIDER_COLOR` | なし | 区切り |
| `GCLOUD_PS1_BG_COLOR` | なし | 全体の背景 |

### 関数で表示や色を決める

シェル関数の名前を指定すると、表示する文字列や色をその関数で決められます。関数は値を引数で受け取り、結果を標準出力に書きます。

| 変数 | 説明 |
| --- | --- |
| `GCLOUD_PS1_ACCOUNT_FUNCTION` / `GCLOUD_PS1_PROJECT_FUNCTION` | 表示する文字列を返す関数 |
| `GCLOUD_PS1_ACCOUNT_COLOR_FUNCTION` / `GCLOUD_PS1_PROJECT_COLOR_FUNCTION` | 色を返す関数 |

## 設定例

本番プロジェクトだけ赤くする:

```bash
_gcloud_project_color() {
  case "$1" in
    *-prod | *-production) echo red ;;
    *) echo green ;;
  esac
}
export GCLOUD_PS1_PROJECT_COLOR_FUNCTION=_gcloud_project_color
```

記号を消して、アカウントは `@` より前だけ表示する:

```bash
export GCLOUD_PS1_SYMBOL_ENABLE=false
export GCLOUD_PS1_ACCOUNT_MODE=user
```

プロジェクト名を短くする:

```bash
_short_project() { echo "${1##*-}"; }
export GCLOUD_PS1_PROJECT_FUNCTION=_short_project
```

## 制限

- 表示するのは、構成ファイルと環境変数(`CLOUDSDK_CORE_PROJECT` など)から分かる値です。`--project` のようにコマンドごとに指定した値は反映されません。
- GCE の VM 上で gcloud がメタデータサーバーから補う値は表示しません(`N/A` になります)。
- 構成ファイルは gcloud が書き出す形式を前提に読みます。手で書き換えた場合は、gcloud 本体と表示が食い違うことがあります。

値の決まり方や構成ファイルの読み方など、細かい仕様は [docs/spec.md](docs/spec.md) にまとめています。

## 開発

```bash
test/run.sh                  # bash と(あれば)zsh でテストを実行
pre-commit install           # コミット前に lint とテストを実行
```

不具合の報告や要望は [Issues](https://github.com/motuneko253/gcloud-ps1/issues) へお願いします。Pull request も歓迎します。

## ライセンス

[MIT](LICENSE)
