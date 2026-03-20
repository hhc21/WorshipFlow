import 'dart:async';

import 'browser_types.dart';

PendingTeamInviteLink? _pendingTeamInviteLink;

Future<bool> copyTextInBrowser(String text) async {
  return false;
}

Future<bool> shareTextLinkInBrowser({
  required String title,
  required String text,
  required String url,
}) async {
  return false;
}

Future<BrowserFileSelection?> pickFileForUpload({
  required String accept,
  Duration timeout = const Duration(seconds: 45),
}) async {
  return null;
}

bool openUrlInNewTab(String url) {
  return false;
}

bool downloadUrlInBrowser(String url, {String? fileName}) {
  return false;
}

BrowserPopupHandle? openBlankPopupWindow() {
  return null;
}

void savePendingTeamInviteLink({
  required String teamId,
  required String inviteCode,
}) {
  _pendingTeamInviteLink = PendingTeamInviteLink(
    teamId: teamId,
    inviteCode: inviteCode,
  );
}

PendingTeamInviteLink? loadPendingTeamInviteLink() {
  return _pendingTeamInviteLink;
}

void clearPendingTeamInviteLink() {
  _pendingTeamInviteLink = null;
}
