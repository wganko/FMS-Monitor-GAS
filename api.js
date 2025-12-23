// ==========================================
// FMS 監視用 GAS スクリプト（CONFIG 一元管理版）
// ==========================================
//
// ・LINE通知の設定（トークン・送信先）
// ・Status / LineUsers シート名
// ・Admin Console 監視ターゲット
// ・mic バックアップ成功レポート条件
// などを CONFIG に集約しています。
// 変更したいときは、基本的にこの CONFIG だけを編集してください。
// ==========================================


// ==========================================
// ダッシュボード用データ取得ロジック
// ==========================================
/**
 * Status シートから「対象サーバーごとの最新1行」を取得して返す
 * 戻り値: [{ serverId, serverLabel, serverName, updatedAt, status, message, ipAddress }, ...]
 */
function getLatestStatusRecords_() {
  // ▼ 対象シートの取得（この GAS が対象スプレッドシートに紐付いている前提）
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName(CONFIG.sheets.statusSheetName);
  if (!sheet) {
    throw new Error('Status シートが見つかりません: ' + CONFIG.sheets.statusSheetName);
  }

  const lastRow = sheet.getLastRow();
  const lastCol = sheet.getLastColumn();

  // データ行が1行もない場合は空配列を返す
  if (lastRow < 2) {
    return [];
  }

  // ▼ 全データをまとめて取得（2 行目～最終行）
  const values = sheet.getRange(2, 1, lastRow - 1, lastCol).getValues();

  // ダッシュボードで表示する対象サーバー名のリスト
  const targetServers = CONFIG.dashboard.targetServers;
  const targetNames = targetServers.map(s => s.name);

  // 結果をサーバー名単位で一時的に保持するオブジェクト
  const latestMap = {};  // key: serverName, value: record

  // ▼ 下から上に向かって走査し、最初に見つかった行を「最新」とみなす
  for (let i = values.length - 1; i >= 0; i--) {
    const row = values[i];

    // 行配列から値を取得（getValues() の戻りは 0 始まり）
    const serverName = row[CONFIG.statusColumns.SERVER_NAME - 1];
    const updatedAt  = row[CONFIG.statusColumns.UPDATED_AT  - 1];
    const status     = row[CONFIG.statusColumns.STATUS      - 1];
    const message    = row[CONFIG.statusColumns.MESSAGE     - 1];
    const ipAddress  = row[CONFIG.statusColumns.IP_ADDRESS  - 1];

    // 対象外サーバーはスキップ
    if (!targetNames.includes(serverName)) {
      continue;
    }

    // すでにそのサーバーの最新行を登録済みならスキップ
    if (latestMap[serverName]) {
      continue;
    }

    // CONFIG.dashboard.targetServers から id / label を取得
    const targetInfo = targetServers.find(t => t.name === serverName) || {
      id: serverName,
      label: serverName
    };

    // 最新行として保存
    latestMap[serverName] = {
      serverId:    targetInfo.id,
      serverLabel: targetInfo.label,
      serverName:  serverName,
      updatedAt:   updatedAt,
      status:      status,
      message:     message,
      ipAddress:   ipAddress
    };

    // すべての対象サーバー分がそろったらループ終了
    if (Object.keys(latestMap).length === targetNames.length) {
      break;
    }
  }

  // latestMap（連想配列）を配列に変換して返す
  return Object.values(latestMap);
}

// ------------------------------------------
// Status 最新行を見て「失敗」だけ LINE 通知
//  - 「完了」は通知しない
//  - 時間ベーストリガーで定期実行想定
// ------------------------------------------
function notifyFailuresFromStatus() {
  const records = getLatestStatusRecords_();
  if (!records || records.length === 0) {
    Logger.log('notifyFailuresFromStatus: 対象レコードなし');
    return;
  }

  records.forEach(rec => {
    const statusStr = String(rec.status || '');
    const failPatterns = (CONFIG.alertKeywords && CONFIG.alertKeywords.fail) || ['失敗'];
    const donePatterns = (CONFIG.alertKeywords && CONFIG.alertKeywords.done) || ['完了'];

    if (donePatterns.some(k => statusStr.indexOf(k) !== -1)) {
      return;
    }
    if (failPatterns.some(k => statusStr.indexOf(k) !== -1)) {
      const ts = rec.updatedAt instanceof Date
        ? Utilities.formatDate(rec.updatedAt, 'Asia/Tokyo', 'yyyy/MM/dd HH:mm:ss')
        : String(rec.updatedAt);

      const msg = [
        '🚨 GAS 実行失敗検知 🚨',
        '',
        'サーバー: ' + (rec.serverLabel || rec.serverName || '-'),
        '時刻: ' + ts,
        '状態: ' + statusStr,
        (rec.message ? '詳細: ' + rec.message : ''),
        (rec.ipAddress ? 'IP: ' + rec.ipAddress : '')
      ].filter(Boolean).join('\n');

      pushMessage(msg);
    }
  });
}

// ==========================================
// ユーティリティ関数
// ==========================================

/**
 * シートを最新 CONFIG.log.maxRows 行（ヘッダー除く）に保つ
 * 超えた分は最古（上側）から削除する
 */
function trimLogRows_(sheet) {
  const lastRow = sheet.getLastRow();
  if (lastRow <= 1) return; // ヘッダーのみ

  const dataRowCount = lastRow - 1; // ヘッダー除外
  if (dataRowCount > CONFIG.log.maxRows) {
    const deleteCount = dataRowCount - CONFIG.log.maxRows;
    sheet.deleteRows(2, deleteCount); // 2行目から古い順に削除
  }
}


// ------------------------------------------
// LINE Messaging API を使ったプッシュ通知（複数宛先対応）
// ------------------------------------------
function pushMessage(text) {
  const token      = CONFIG.line.channelAccessToken;
  const recipients = CONFIG.line.recipients || [];

  if (!token || recipients.length === 0) {
    Logger.log('ERROR: LINE Token or recipients are missing in configuration.');
    return;
  }

  const url = 'https://api.line.me/v2/bot/message/push';

  recipients.forEach(rec => {
    const headers = {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer ' + token
    };

    const payload = {
      to: rec.id,
      messages: [{
        type: 'text',
        text: text
      }]
    };

    const options = {
      method: 'post',
      headers: headers,
      payload: JSON.stringify(payload)
    };

    try {
      UrlFetchApp.fetch(url, options);
    } catch (e) {
      Logger.log('pushMessage error for ' + rec.id + ': ' + e);
    }
  });
}


// ------------------------------------------
// Status シートを取得する（なければ作る）
// ------------------------------------------
function getStatusSheet() {
  const ss        = SpreadsheetApp.getActiveSpreadsheet();
  const sheetName = CONFIG.sheets.statusSheetName;
  let sheet       = ss.getSheetByName(sheetName);
  if (!sheet) {
    sheet = ss.insertSheet(sheetName);
    sheet.appendRow(['Server', 'LastUpdated', 'Status', 'Message', 'IP']);
  }
  return sheet;
}

// ------------------------------------------
// LineUsers シートを取得する（なければ作る）
//  （Webhook の生ログ保存用）
// ------------------------------------------
function getLineUserSheet() {
  const ss        = SpreadsheetApp.getActiveSpreadsheet();
  const sheetName = CONFIG.sheets.lineUserSheetName;
  let sheet       = ss.getSheetByName(sheetName);
  if (!sheet) {
    sheet = ss.insertSheet(sheetName);
    sheet.appendRow(['Timestamp', 'UserID', 'Message', 'RawJSON']);
  }
  return sheet;
}


// ------------------------------------------
// Status に「1行追記」するだけの関数（上書き禁止）
// ------------------------------------------
function appendStatusLog(name, time, status, msg, ip) {
  const sheet = getStatusSheet();
  if (!sheet) return;

  const formattedTime =
    Utilities.formatDate(time, 'Asia/Tokyo', 'yyyy/MM/dd HH:mm:ss');

  sheet.appendRow([
    name,          // A列: サーバー名
    formattedTime, // B列: 最終更新日時
    status,        // C列: ステータス
    msg,           // D列: 詳細メッセージ
    ip             // E列: IPアドレス
  ]);
  trimLogRows_(sheet);
}

// ------------------------------------------
// LINE Webhook イベントを LineUsers シートに保存
// ------------------------------------------
function logLineWebhookEvent(eventData) {
  const sheet = getLineUserSheet();
  const events = eventData.events || [];

  events.forEach(ev => {
    const source = ev.source || {};
    const userId = source.userId || '';
    let msgText  = '';

    if (ev.message && ev.message.type === 'text') {
      msgText = ev.message.text || '';
    } else {
      msgText = '(non-text)';
    }

    sheet.appendRow([
      new Date(),               // Timestamp
      userId,                   // UserID
      msgText,                  // Message
      JSON.stringify(eventData) // RawJSON
    ]);
  });
}


// ==========================================
// SSL 期限チェック（主に ant 側用）
// ==========================================
function checkSslExpiry(serverName, expiryDateString) {
  const WARN_DAYS = CONFIG.sslThreshold.warnDays;
  const CRIT_DAYS = CONFIG.sslThreshold.critDays;

  const expiryDate = new Date(expiryDateString);
  if (isNaN(expiryDate.getTime())) {
    Logger.log('checkSslExpiry: 期限日付の解析に失敗: ' + expiryDateString);
    return;
  }

  const now      = new Date();
  const diffMs   = expiryDate.getTime() - now.getTime();
  const daysLeft = Math.floor(diffMs / (1000 * 60 * 60 * 24));

  if (daysLeft < 0) {
    const msg =
      '🚨 SSL証明書 期限切れ 🚨\n\n' +
      '[サーバー] ' + serverName + '\n' +
      '[期限] ' +
      Utilities.formatDate(expiryDate, 'Asia/Tokyo', 'yyyy/MM/dd HH:mm') + '\n' +
      '[残り日数] ' + daysLeft + ' 日（すでに切れています）';
    pushMessage(msg);
    return;
  }

  if (daysLeft < CRIT_DAYS) {
    const msg =
      '🚨 SSL証明書 有効期限が非常に近いです 🚨\n\n' +
      '[サーバー] ' + serverName + '\n' +
      '[期限] ' +
      Utilities.formatDate(expiryDate, 'Asia/Tokyo', 'yyyy/MM/dd HH:mm') + '\n' +
      '[残り日数] ' + daysLeft + ' 日';
    pushMessage(msg);
    return;
  }

  if (daysLeft < WARN_DAYS) {
    const msg =
      '⚠️ SSL証明書 有効期限が近づいています ⚠️\n\n' +
      '[サーバー] ' + serverName + '\n' +
      '[期限] ' +
      Utilities.formatDate(expiryDate, 'Asia/Tokyo', 'yyyy/MM/dd HH:mm') + '\n' +
      '[残り日数] ' + daysLeft + ' 日';
    pushMessage(msg);
    return;
  }

  Logger.log(
    'checkSslExpiry: ' + serverName + ' は SSL 残り ' +
    daysLeft + ' 日（通知不要ゾーン）。'
  );
}


// ==========================================
// ant の Admin Console 外形監視（任意）
// → 時間ベーストリガーで呼び出し
// ==========================================
function checkFmsAdminConsoles() {
  const TARGETS = CONFIG.adminConsoleTargets;

  TARGETS.forEach(target => {
    const HOST = target.host;
    const URL  = 'https://' + HOST + '/admin-console';

    let isError = false;
    let msgList = [];

    try {
      const response = UrlFetchApp.fetch(URL, {
        muteHttpExceptions: true,
        followRedirects: true
      });

      const code = response.getResponseCode();

      if (code < 200 || code >= 400) {
        isError = true;
        msgList.push(
          '外部アクセスエラー: Admin Console が正常に応答しません (HTTP ' +
          code + ')。'
        );
      }

    } catch (e) {
      isError = true;
      msgList.push(
        '外部アクセスエラー: ' + URL + ' へのHTTPS接続に失敗しました。' +
        ' DDNS・ポート転送・証明書設定などを確認してください。詳細: ' + e
      );
    }

    if (isError) {
      const lineMessage =
        '🚨 FMS 稼働監視エラー 🚨\n\n' +
        '[対象] ' + target.id + ' (' + HOST + ')\n' +
        '[チェックURL] ' + URL + '\n' +
        '[内容]\n- ' + msgList.join('\n- ');

      pushMessage(lineMessage);

      appendStatusLog(
        'GAS FMS Monitor (' + target.id + ')',
        new Date(),
        'CRITICAL',
        msgList.join(' | '),
        HOST
      );

    } else {
      appendStatusLog(
        'GAS FMS Monitor (' + target.id + ')',
        new Date(),
        'OK',
        target.memo + ' へのHTTPS接続OK',
        HOST
      );
    }
  });
}


// ==========================================
// サーバーからの監視データを処理
// （PowerShell / シェル からの JSON 用）
// ==========================================
function processServerReport(params) {
  const serverName       = params.server;
  const status           = params.status;
  const message          = params.message;
  const ip               = params.ip || '-';
  const expiryDateString = params.expiryDateString; // ant 側のみ

  // ★ 毎回「履歴として」追記
  appendStatusLog(serverName, new Date(), status, message, ip);

  // ERROR のときだけ LINE 通知
  if (status === 'ERROR') {
    const text =
      '🚨 サーバー異常検知 🚨\n\n' +
      '[サーバー] ' + serverName + '\n' +
      '[状態] ' + message + '\n' +
      '[時間] ' +
      Utilities.formatDate(new Date(), 'Asia/Tokyo', 'MM/dd HH:mm');
    pushMessage(text);
  }

  // mic.kwgi.org のバックアップ成功だけ定時レポート
  // const micConf = CONFIG.micBackupReport;
  // if (
  //   serverName === micConf.serverName &&
  //   status === 'INFO' &&
  //   message.indexOf(micConf.successKeyword) !== -1
  // ) {
  //   const text =
  //     '✅ 定時レポート\n\n' +
  //     '[サーバー] ' + serverName + '\n' +
  //     '[内容] ' + message;
  //   pushMessage(text);
  // }

  // ant 側の SSL 期限チェック用
  if (expiryDateString) {
    checkSslExpiry(serverName, expiryDateString);
  }
}

// ------------------------------------------
// Admin Console 用 URL を CONFIG から組み立てる
// ------------------------------------------
function buildAdminConsoleUrl_(target) {
  const c = CONFIG.adminConsole;

  const scheme   = c.scheme || 'https';
  const portPart = c.port ? ':' + c.port : '';   // null or undefined のときは付けない
  const pathPart = c.path || '';

  return scheme + '://' + target.host + portPart + pathPart;
}

// ------------------------------------------
// Admin Console 外形監視（1ターゲット分）
// 設定値はすべて CONFIG から取得
// ------------------------------------------
function checkAdminConsoleTarget_(target) {
  const url = buildAdminConsoleUrl_(target);  // ← URL はここで完結

  const options = {
    muteHttpExceptions: true,
    followRedirects: CONFIG.adminConsole.followRedirects,
    timeout: CONFIG.adminConsole.timeoutMs
  };

  try {
    const res    = UrlFetchApp.fetch(url, options);
    const status = res.getResponseCode();

    if (status >= 200 && status < 400) {
      // HTTP レベルで正常に応答している
      return {
        id:   target.id,
        host: target.host,
        memo: target.memo || '',
        ok:   true,                // ← 後で allUp / allDown 判定に使う
        code: status,
        message: 'HTTP ' + status + ' 応答あり'
      };
    } else {
      // HTTP 応答はあるがステータスがエラー
      return {
        id:   target.id,
        host: target.host,
        memo: target.memo || '',
        ok:   false,
        code: status,
        message: 'HTTP ' + status + ' 異常ステータス'
      };
    }
  } catch (e) {
    // そもそも接続できない（DNS / ルーター / 回線など）
    return {
      id:   target.id,
      host: target.host,
      memo: target.memo || '',
      ok:   false,
      code: null,
      message: '接続エラー: ' + e
    };
  }
}

// ------------------------------------------
// Admin Console 外形監視（ant 1台専用）
//  - CONFIG.adminConsoleTargets に ant だけ入っている前提
//  - ant に到達できなければ
//    「ant またはネットワーク異常の可能性」として通知
// ------------------------------------------
function monitorAdminConsoles() {
  const targets = CONFIG.adminConsoleTargets;

  if (!targets || targets.length === 0) {
    Logger.log('CONFIG.adminConsoleTargets が設定されていません。');
    return;
  }

  // 1台だけの前提なので先頭要素を取り出す
  const target = targets[0];

  // ant の Admin Console に外形監視
  const result = checkAdminConsoleTarget_(target);

  // ログ（任意）
  Logger.log(JSON.stringify(result, null, 2));

  // ok=true → 正常なので何もしない
  if (result.ok) {
    return;
  }

  // ok=false → ant かネットワークのどちらかに問題がある
  const msg = buildSingleServerOrNetworkAlertMessage_(result);
  pushMessage(msg);   // 既存の LINE 送信関数
}

// ------------------------------------------
// ant または事務所ネットワーク異常の可能性メッセージ
//  - 外部(GAS)から ant.kwgi.org/admin-console に到達できなかったとき
// ------------------------------------------
function buildSingleServerOrNetworkAlertMessage_(result) {
  const now = Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy/MM/dd HH:mm:ss');

  const body = [
    '🚨【ant またはネットワーク異常の可能性】🚨',
    '',
    '時刻: ' + now,
    'ホスト: ' + result.host,
    (result.memo ? 'メモ: ' + result.memo : ''),
    '',
    'GAS（クラウド）から ant の Admin Console に接続できませんでした。',
    '',
    '想定される原因:',
    '  - ant.kwgi.org 上の FileMaker Server / OS 停止',
    '  - 川東校区コミュニティ協議会事務所内の pikara ルーター / ONU / 回線障害',
    '',
    '技術情報: ' + result.message
  ];

  return body.join('\n');
}

// ==========================================
// doPost: LINE Webhook or サーバー監視レポート
// ==========================================
function doPost(e) {
  const body = (e.postData && e.postData.contents)
    ? e.postData.contents
    : '{}';

  let data;
  try {
    data = JSON.parse(body);
  } catch (err) {
    Logger.log('ERROR in doPost(JSON.parse): ' + err);
    return ContentService.createTextOutput(
      'Error: Invalid JSON'
    );
  }

  // 1) LINE Webhook （destination / events がある）
  if (data.destination && data.events && data.events.length > 0) {
    logLineWebhookEvent(data);
    return ContentService.createTextOutput('OK');
  }

  // 2) サーバー監視レポート（server / status がある）
  if (data.server && data.status) {
    processServerReport(data);
    return ContentService.createTextOutput('Report Processed');
  }

  // 3) それ以外（今回は使わない）
  Logger.log('doPost: Unknown payload: ' + body);
  return ContentService.createTextOutput('Ignored');
}



// ==========================================
// テスト用：LINE 通知が全員に届くか確認
// ==========================================
function testLineRecipients() {
  pushMessage('【テスト】FMS監視 LINE 通知の受信確認です。');
}
