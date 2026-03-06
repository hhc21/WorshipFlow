enum TeamRole { admin, leader, member }

TeamRole normalizeTeamRole(String? role) {
  final normalized = (role ?? '').trim().toLowerCase();
  switch (normalized) {
    case 'admin':
    case 'owner':
    case 'team_admin':
    case '팀장':
      return TeamRole.admin;
    case 'leader':
    case 'speaker':
    case '인도자':
      return TeamRole.leader;
    case 'member':
    case '팀원':
    default:
      return TeamRole.member;
  }
}

String teamRoleKey(String? role) {
  switch (normalizeTeamRole(role)) {
    case TeamRole.admin:
      return 'admin';
    case TeamRole.leader:
      return 'leader';
    case TeamRole.member:
      return 'member';
  }
}

String teamRoleLabel(String? role) {
  switch (normalizeTeamRole(role)) {
    case TeamRole.admin:
      return '팀장';
    case TeamRole.leader:
      return '인도자';
    case TeamRole.member:
      return '팀원';
  }
}

bool isAdminRole(String? role) => normalizeTeamRole(role) == TeamRole.admin;

bool isLeaderRole(String? role) => normalizeTeamRole(role) == TeamRole.leader;
