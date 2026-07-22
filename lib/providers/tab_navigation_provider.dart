import 'package:flutter/material.dart';

class TabNavigationProvider with ChangeNotifier {
  int _currentTab = 0;

  int get currentTab => _currentTab;

  void setTab(int index) {
    _currentTab = index;
    notifyListeners();
  }

  void navigateToTab(BuildContext context, int index) {
    setTab(index);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
