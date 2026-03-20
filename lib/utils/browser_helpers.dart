import 'dart:async';

import 'browser_helpers_stub.dart'
    if (dart.library.html) 'browser_helpers_web.dart'
    as impl;
import 'browser_types.dart';

Future<bool> copyTextInBrowser(String text) => impl.copyTextInBrowser(text);

Future<bool> shareTextLinkInBrowser({
  required String title,
  required String text,
  required String url,
}) => impl.shareTextLinkInBrowser(title: title, text: text, url: url);

Future<BrowserFileSelection?> pickFileForUpload({
  required String accept,
  Duration timeout = const Duration(seconds: 45),
}) => impl.pickFileForUpload(accept: accept, timeout: timeout);

bool openUrlInNewTab(String url) => impl.openUrlInNewTab(url);

bool downloadUrlInBrowser(String url, {String? fileName}) =>
    impl.downloadUrlInBrowser(url, fileName: fileName);

BrowserPopupHandle? openBlankPopupWindow() => impl.openBlankPopupWindow();

void savePendingTeamInviteLink({
  required String teamId,
  required String inviteCode,
}) => impl.savePendingTeamInviteLink(teamId: teamId, inviteCode: inviteCode);

PendingTeamInviteLink? loadPendingTeamInviteLink() =>
    impl.loadPendingTeamInviteLink();

void clearPendingTeamInviteLink() => impl.clearPendingTeamInviteLink();
