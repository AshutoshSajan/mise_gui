import 'package:flutter/material.dart';

enum AppDestination {
  dashboard(
    label: 'Overview',
    description: 'Environment overview',
    path: '/dashboard',
    icon: Icons.space_dashboard_rounded,
    selectedIcon: Icons.dashboard_customize_rounded,
  ),
  tools(
    label: 'Tools',
    description: 'Tool versions',
    path: '/tools',
    icon: Icons.handyman_outlined,
    selectedIcon: Icons.handyman_rounded,
  ),
  projects(
    label: 'Projects',
    description: 'Project overrides',
    path: '/projects',
    icon: Icons.workspaces_outline,
    selectedIcon: Icons.workspaces_rounded,
  ),
  config(
    label: 'Config',
    description: 'Global config',
    path: '/config',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune_rounded,
  );

  const AppDestination({
    required this.label,
    required this.description,
    required this.path,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final String description;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  static AppDestination fromLocation(String location) {
    return AppDestination.values.firstWhere(
      (destination) => location.startsWith(destination.path),
      orElse: () => AppDestination.dashboard,
    );
  }
}
