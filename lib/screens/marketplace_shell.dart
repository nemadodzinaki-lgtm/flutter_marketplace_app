import 'package:flutter/material.dart';

import '../widgets/unread_messages_badge.dart';

import 'create_listing_screen.dart';
import 'marketplace_home_screen.dart';
import 'messages_inbox_screen.dart';
import 'my_listings_screen.dart';
import 'advanced_search_screen.dart';

/// The main navigation for signed-in users.
///
/// Existing pages are reused without replacing their working logic.
/// The Post destination opens Create Listing as a separate page.
class MarketplaceShell extends StatefulWidget {
  final String firstName;

  const MarketplaceShell({super.key, required this.firstName});

  @override
  State<MarketplaceShell> createState() => _MarketplaceShellState();
}

class _MarketplaceShellState extends State<MarketplaceShell> {
  static const Color green = Color(0xFF16803C);

  // NavigationBar indices: 0 Home, 1 Explore, 2 Post, 3 Messages, 4 Mine.
  // Index 2 opens a new page and is never stored as the active tab.
  int _selectedTab = 0;
  final Set<int> _visitedTabs = {0};

  // Refresh a page when returning to it so new listings/messages are visible.
  int _homeVersion = 0;
  int _inboxVersion = 0;
  int _myListingsVersion = 0;

  int get _stackIndex {
    switch (_selectedTab) {
      case 1:
        return 1;
      case 3:
        return 2;
      case 4:
        return 3;
      default:
        return 0;
    }
  }

  Future<void> _openCreateListing() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateListingScreen()),
    );

    if (!mounted) return;

    if (created == true) {
      setState(() {
        _homeVersion++;
        _myListingsVersion++;
        _selectedTab = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listing published successfully!'),
          backgroundColor: green,
        ),
      );
    }
  }

  void _selectTab(int index) {
    if (index == 2) {
      _openCreateListing();
      return;
    }

    if (index == _selectedTab) return;

    setState(() {
      _selectedTab = index;
      _visitedTabs.add(index);

      if (index == 0) _homeVersion++;
      if (index == 3) _inboxVersion++;
      if (index == 4) _myListingsVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Pages already have their own Scaffold and AppBar. Keeping those
      // unchanged avoids breaking their existing buttons and navigation.
      body: IndexedStack(
        index: _stackIndex,
        children: [
          MarketplaceHomeScreen(
            key: ValueKey('home-$_homeVersion'),
            firstName: widget.firstName,
          ),
          _visitedTabs.contains(1)
              ? const AdvancedSearchScreen()
              : const SizedBox.shrink(),
          _visitedTabs.contains(3)
              ? MessagesInboxScreen(key: ValueKey('inbox-$_inboxVersion'))
              : const SizedBox.shrink(),
          _visitedTabs.contains(4)
              ? MyListingsScreen(key: ValueKey('my-$_myListingsVersion'))
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: _selectTab,
        backgroundColor: const Color(0xFFF7F9F8),
        indicatorColor: const Color(0xFFE5F4E9),
        labelBehavior:
            MediaQuery.sizeOf(context).width < 360 &&
                MediaQuery.textScalerOf(context).scale(11) > 14
            ? NavigationDestinationLabelBehavior.onlyShowSelected
            : NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: green),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.travel_explore_outlined),
            selectedIcon: Icon(Icons.travel_explore, color: green),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_rounded, color: green, size: 30),
            selectedIcon: Icon(Icons.add_circle_rounded, color: green),
            label: 'Post',
          ),
          NavigationDestination(icon: UnreadMessagesBadge(), label: 'Messages'),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded, color: green),
            label: 'My Listings',
          ),
        ],
      ),
    );
  }
}
