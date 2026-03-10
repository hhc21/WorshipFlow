import 'package:flutter/widgets.dart';

import 'next_viewer_contract.dart';
import 'next_viewer_host_stub.dart'
    if (dart.library.html) 'next_viewer_host_web.dart'
    as impl;

class NextViewerHostView extends StatelessWidget {
  final NextViewerHostProps props;

  const NextViewerHostView({super.key, required this.props});

  @override
  Widget build(BuildContext context) {
    return impl.buildNextViewerHostView(props);
  }
}
