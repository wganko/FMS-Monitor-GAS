// ==========================================
// Webアプリ入口（ダッシュボード表示）
// ==========================================
/**
 * Web アプリ公開用エントリポイント
 * dashboard.html テンプレートに最新ステータス情報を埋め込んで返す
 */
function doGet(e) {
    // HTML テンプレートの読み込み
    // ファイル名が「dashboard.html」なので 'dashboard' を指定
    const template = HtmlService.createTemplateFromFile('dashboard');
  
    // スプレッドシートからダッシュボード用データを取得
    const records = getLatestStatusRecords_();
  
    // テンプレートへ JSON 文字列として埋め込む
    template.recordsJson = JSON.stringify(records);
  
    // HTML を評価してレスポンスとして返す
    return template
      .evaluate()
      .setTitle('FMS Monitor Dashboard')
      .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
  }
  