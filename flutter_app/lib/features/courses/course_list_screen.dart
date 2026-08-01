import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../../providers/course_providers.dart';
import 'widgets/course_card.dart';

class CourseListScreen extends ConsumerStatefulWidget {
  const CourseListScreen({super.key});

  @override
  ConsumerState<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends ConsumerState<CourseListScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const _levels = ['beginner', 'intermediate', 'advanced'];

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesListProvider);
    final filter = ref.watch(courseFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Courses')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search courses...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(courseFilterProvider.notifier).state =
                              filter.copyWith(search: '');
                        },
                      )
                    : null,
              ),
              onSubmitted: (value) {
                ref.read(courseFilterProvider.notifier).state =
                    filter.copyWith(search: value);
              },
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _LevelChip(
                  label: 'All levels',
                  selected: filter.level == null,
                  onTap: () => ref.read(courseFilterProvider.notifier).state =
                      filter.copyWith(clearLevel: true),
                ),
                for (final level in _levels)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _LevelChip(
                      label: level,
                      selected: filter.level == level,
                      onTap: () => ref.read(courseFilterProvider.notifier).state =
                          filter.copyWith(level: level),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(coursesListProvider),
              child: coursesAsync.when(
                data: (courses) {
                  if (courses.isEmpty) {
                    return const EmptyView(
                      message: 'No courses match your search.',
                      icon: Icons.search_off_rounded,
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: courses.length,
                    itemBuilder: (context, index) {
                      final course = courses[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CourseCard(
                          course: course,
                          onTap: () => context.push('/courses/${course.id}'),
                        ),
                      );
                    },
                  );
                },
                loading: () => const LoadingView(),
                error: (e, __) => ErrorView(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(coursesListProvider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label[0].toUpperCase() + label.substring(1)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withOpacity(0.15),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
