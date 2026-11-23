# 仕様の詳細

README に書いていない細かい挙動をまとめています。

## 動作を確認した環境

| シェル | バージョン |
| --- | --- |
| bash | 3.2 / 4.4 / 5.2 |
| zsh | 5.9 |

bash 3.2 と 4.4 は Linux 上(Docker の公式イメージ)で確認しています。macOS の実機では確認していません。

## 値の決まり方

gcloud 本体と同じ優先順位です。

| 項目 | 優先順位 |
| --- | --- |
| アカウント | 環境変数 `CLOUDSDK_CORE_ACCOUNT` → 構成の `[core] account` |
| プロジェクト | 環境変数 `CLOUDSDK_CORE_PROJECT` → 構成の `[core] project` |
| impersonate | 環境変数 `CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT` → 構成の `[auth] impersonate_service_account` |
| 構成名 | 環境変数 `CLOUDSDK_ACTIVE_CONFIG_NAME` → `active_config` ファイル → `default` |

- 構成ファイルの場所は `$CLOUDSDK_CONFIG`(未設定なら `~/.config/gcloud`)です。
- アカウント・プロジェクト・impersonate の環境変数は、空文字で定義されていても構成ファイルより優先します。
- `HOME` も `CLOUDSDK_CONFIG` も未設定のときは、構成ファイルを読みません。

## 構成名

- 環境変数 `CLOUDSDK_ACTIVE_CONFIG_NAME` は形式を検証せず、そのまま `config_<名前>` を読みます。ファイルが無ければ `N/A` です。`/` を含む名前は拒否します。
- `active_config` ファイルの中身が `^[a-z][-a-z0-9]*$` に合わないとき、または空のときは `default` として扱います。
- 名前の末尾に改行があるとき(`echo foo > active_config` で書いた場合など)は、その名前のファイルが存在しないため `N/A` になります。gcloud 本体でも値なしになります。CRLF も同じです。
- `NONE` は「構成なし」として `N/A` を表示します。

## 構成ファイルの読み取り

gcloud は Python の `configparser` で構成ファイルを読みます。このスクリプトは、gcloud が書き出す形式に絞って読みます。

対応しているもの:

- `key = value` と `key: value`(区切りは最初に現れる `=` か `:`)
- 見出し行の後ろのコメント(`[core] # comment`)
- 直前のキーより深く字下げされた継続行(読み飛ばします)

対応していないもの:

- 大文字を含むキー(`Project = x` など)
- `%(...)s` による値の補間
- `[DEFAULT]` セクションの継承
- SDK のインストール先にある `properties` ファイル

通常のファイル以外(FIFO など)は読みません。

## 表示する値の加工

構成ファイルや環境変数の内容が、プロンプトの制御に使われないようにしています。

- 256 文字を超える値は切り詰めます(超えた分は `…` になります)。
- 制御文字は取り除きます。
- zsh では `%` をエスケープします。

`GCLOUD_PS1_PREFIX` などの設定値は加工しません。

## 関数に渡る値

- 呼ばれるのは、現在のシェルで定義済みのシェル関数だけです。外部コマンドは実行しません。
- 関数が未定義、または失敗したときは、元の値と既定の色を使います。
- 表示を返す関数には、`GCLOUD_PS1_ACCOUNT_MODE` を適用した後の値が渡ります。値が無いときは `N/A`(`GCLOUD_PS1_NA` の値)が渡ります。
- 色を返す関数には、加工する前の値が渡ります。値が無いときは空文字が渡ります。
- 関数を 1 つ指定するごとに、プロンプトの描画でサブシェルが 1 つ増えます。指定しなければ、`$(gcloud_ps1)` 以外にサブシェルは作りません。

## 表示の切り替え

- `gcloudoff -g` は `${XDG_CONFIG_HOME:-$HOME/.config}/gcloud-ps1/disabled` というファイルを作り、`gcloudon -g` はそれを消します。
- `-g` なしの設定(環境変数 `GCLOUD_PS1_ENABLED`)は、そのシェルの中で全体の設定より優先されます。
- `GCLOUD_PS1_ACCOUNT_ENABLE=false` のときに impersonate 先がある場合は、矢印を付けずにサービスアカウントだけを表示します。

## そのほか

- `gcloud_ps1` は直前のコマンドの終了コードをそのまま返します。プロンプトの後ろのほうで `$?` を表示していても、値は変わりません。
- zsh では `PROMPT_SUBST` を有効にします。

## 開発

```bash
shellcheck -s bash gcloud-ps1.sh test/run.sh test/cases.sh
shfmt -d gcloud-ps1.sh test/run.sh test/cases.sh
test/run.sh
```

- `test/run.sh` は bash と(入っていれば)zsh でテストを実行します。構成ファイルは一時ディレクトリに作るので、実際の gcloud の設定には触れません。
- 使うシェルは `GCLOUD_PS1_TEST_SHELLS="bash /path/to/zsh" test/run.sh` のように指定できます。
- [pre-commit](https://pre-commit.com/) で、コミット前に `shellcheck`、`shfmt`、テスト、[gitleaks](https://github.com/gitleaks/gitleaks) を実行します。
- GitHub Actions でも同じ内容を実行します。あわせて、bash 3.2 と 4.4 でのテストと、履歴全体への gitleaks を実行します。
