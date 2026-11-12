import 'package:flutter/material.dart';

/// Placeholder until an opportunities table is added to the Supabase schema.
class JobseekerOpportunityDiscoveryScreen extends StatelessWidget {
  const JobseekerOpportunityDiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF4F8FA),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore_outlined, size: 48),
              SizedBox(height: 14),
              Text(
                'Opportunity discovery is not connected yet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'This project currently uses Supabase. Connect this screen '
                'to a Supabase opportunities table to show listings here.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
