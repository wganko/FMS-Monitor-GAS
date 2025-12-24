
// ==========================================
// 設定エリア（ここだけ直せばよい）
// ==========================================
const CONFIG = {
    // --- LINE 関連設定 ---
    line: {
      channelAccessToken: 'y/Nk4xrQ4+zcAB3pLTp6D3Y6O5Bd+4wDbuJXbbxtJ1gqAFAjCDftBpacX2ZJxYdTYXd+vbSgag4f5ooF8AS4S2YPugghKMPtyx1Jm7EH7ftYDWf+io9hMNfgOLZU3am87DyvHQJM5DseXIOPzDfK4QdB04t89/1O/w1cDnyilFU=',
      recipients: [
        { type: 'user', id: 'Ud3908d2fe1dc4a144c32378bbbc781a5' },
        { type: 'user', id: 'Uff6fa3d8032b2ccdc9c38993eb1434ec' }
      ]
    },
  
    // --- スプレッドシート関連 ---
    sheets: {
      statusSheetName: 'Status',
      lineUserSheetName: 'LineUsers'
    },
  
    // --- Admin Console 外形監視ターゲット ---
    adminConsoleTargets: [
      { id: 'ant', host: 'ant.kwgi.org', memo: 'ant FileMaker Server Admin Console' }
    //  { id: 'mic', host: 'mic.kwgi.org', memo: 'mic FileMaker Server Admin Console' }
    ],
  
    // ★ Admin Console 共通設定（関数内に直書き禁止）
    adminConsole: {
      scheme: 'https',          // http / https
      port:   null,             // 443 のときは null でOK（URLに :443 を付けない）
      path:   '/admin-console/',// 今回ここが重要
      timeoutMs: 10000,         // タイムアウト(ms)
      followRedirects: false    // リダイレクト追跡の有無
    },
  
    // --- mic バックアップ成功レポート通知条件 ---
    micBackupReport: {
      serverName:     'mic.kwgi.org',
      successKeyword: 'FileMaker Serverバックアップと復元に成功しました'
    },
  
    dashboard: {
      targetServers: [
        { id: 'ant', name: 'ant.kwgi.org', label: 'ant.kwgi.org' },
        { id: 'mic', name: 'mic.kwgi.org', label: 'mic.kwgi.org' }
      ]
    },
  
    sslThreshold: {
      warnDays: 30,
      critDays: 7
    },
  
    // --- ログ管理用 ---
    log: {
      maxRows: 30         // Status に保持する最大行数（ヘッダー除く）
    },
  
    // --- ステータスシート列番号定義 ---
    statusColumns: {
      SERVER_NAME: 1,   // A列: サーバー名
      UPDATED_AT:  2,   // B列: 最終更新日時
      STATUS:      3,   // C列: ステータス
      MESSAGE:     4,   // D列: 詳細メッセージ
      IP_ADDRESS:  5    // E列: IPアドレス
    },

    // --- 失敗/完了 判定語句（部分一致） ---
    alertKeywords: {
      fail: ['失敗', '失敗しました', 'エラー', 'ERROR'],
      done: ['完了', '成功', 'RECOVERED']
    }
  };
  