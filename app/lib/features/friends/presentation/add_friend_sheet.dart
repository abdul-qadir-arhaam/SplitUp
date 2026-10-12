import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../data/friends_repository.dart';

class ContactEntry {
  final String id;
  final String displayName;
  final String rawPhone;
  final String cleanPhone;
  final bool isAppUser;
  final bool isAlreadyFriend;

  const ContactEntry({
    required this.id,
    required this.displayName,
    required this.rawPhone,
    required this.cleanPhone,
    required this.isAppUser,
    required this.isAlreadyFriend,
  });
}

class AddFriendSheet extends ConsumerStatefulWidget {
  const AddFriendSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddFriendSheet(),
    );
  }

  @override
  ConsumerState<AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends ConsumerState<AddFriendSheet> {
  // Tab: 0 = Contacts, 1 = Manual Entry
  int _selectedTab = 0;

  // Manual Entry Form
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _searchController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingContacts = false;
  bool? _permissionGranted;

  List<StoredUserAccount> _registeredUsers = [];
  Set<String> _registeredPhoneSet = {};
  Set<String> _existingFriendPhoneSet = {};

  List<ContactEntry> _allContacts = [];
  List<ContactEntry> _filteredContacts = [];

  StoredUserAccount? _detectedManualAppUser;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadRegisteredUsersAndFriends();
    _requestAndLoadContacts();
  }

  Future<void> _loadRegisteredUsersAndFriends() async {
    try {
      final currentUserId = ref.read(authNotifierProvider).user?.id;
      final accounts = await ref.read(authServiceProvider).getStoredAccounts();
      final friends = ref.read(friendsNotifierProvider).asData?.value ?? [];

      _existingFriendPhoneSet = friends
          .map((f) => _cleanTo10Digits(f.phoneE164))
          .where((p) => p.isNotEmpty)
          .toSet();

      // Accounts excluding current user
      _registeredUsers = accounts.where((a) {
        if (a.id == currentUserId || a.id == 'usr_arhaam') return false;
        return true;
      }).toList();

      _registeredPhoneSet = _registeredUsers
          .map((a) => _cleanTo10Digits(a.phone))
          .where((p) => p.isNotEmpty)
          .toSet();

      if (mounted) setState(() {});
    } catch (_) {}
  }

  String _cleanTo10Digits(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  Future<void> _requestAndLoadContacts() async {
    setState(() => _isLoadingContacts = true);

    if (kIsWeb) {
      // In web browser: Provide sample phone contacts for testing
      _loadWebFallbackContacts();
      setState(() {
        _permissionGranted = true;
        _isLoadingContacts = false;
      });
      return;
    }

    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      final isGranted = status == PermissionStatus.granted;

      if (!isGranted) {
        if (mounted) {
          setState(() {
            _permissionGranted = false;
            _isLoadingContacts = false;
          });
        }
        return;
      }

      final rawContacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone},
      );

      final List<ContactEntry> parsed = [];
      final Set<String> seenPhones = {};

      for (final c in rawContacts) {
        final name = (c.displayName ?? '').trim();
        if (name.isEmpty) continue;

        for (final p in c.phones) {
          final clean = _cleanTo10Digits(p.number);
          if (clean.length == 10 && !seenPhones.contains(clean)) {
            seenPhones.add(clean);
            final isAppUser = _registeredPhoneSet.contains(clean);
            final isFriend = _existingFriendPhoneSet.contains(clean);

            parsed.add(ContactEntry(
              id: c.id ?? clean,
              displayName: name,
              rawPhone: p.number,
              cleanPhone: clean,
              isAppUser: isAppUser,
              isAlreadyFriend: isFriend,
            ));
          }
        }
      }

      // Sort: App users first, then alphabetically
      parsed.sort((a, b) {
        if (a.isAppUser && !b.isAppUser) return -1;
        if (!a.isAppUser && b.isAppUser) return 1;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });

      if (mounted) {
        setState(() {
          _permissionGranted = true;
          _allContacts = parsed;
          _filteredContacts = parsed;
          _isLoadingContacts = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _permissionGranted = false;
          _isLoadingContacts = false;
        });
      }
    }
  }

  Future<void> _pickNativeContact() async {
    if (kIsWeb) return;
    try {
      final contact = await FlutterContacts.native.showPicker();
      if (contact != null && contact.phones.isNotEmpty) {
        final rawName = (contact.displayName ?? '').trim();
        final name = rawName.isNotEmpty ? rawName : 'Friend';
        final clean = _cleanTo10Digits(contact.phones.first.number);
        final isAppUser = _registeredPhoneSet.contains(clean);

        if (isAppUser) {
          await _addFriendDirectly(phone: clean, name: name, isAppUser: true);
        } else {
          await _addAndInviteViaSms(phone: clean, name: name);
        }
      }
    } catch (_) {}
  }

  void _loadWebFallbackContacts() {
    final samples = [
      {'name': 'Rahul Sharma', 'phone': '9876543210'},
      {'name': 'Priya Patel', 'phone': '9812345678'},
      {'name': 'Aman Gupta', 'phone': '9988776655'},
      {'name': 'Sneha Rao', 'phone': '9123456789'},
      {'name': 'Vikram Singh', 'phone': '9871234560'},
      {'name': 'Ananya Das', 'phone': '9711223344'},
      {'name': 'Rohan Mehta', 'phone': '9899001122'},
    ];

    final List<ContactEntry> list = [];
    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      final clean = _cleanTo10Digits(s['phone']!);
      final isAppUser = _registeredPhoneSet.contains(clean) || i < 2;
      final isFriend = _existingFriendPhoneSet.contains(clean);

      list.add(ContactEntry(
        id: 'mock_$i',
        displayName: s['name']!,
        rawPhone: '+91 ${s['phone']}',
        cleanPhone: clean,
        isAppUser: isAppUser,
        isAlreadyFriend: isFriend,
      ));
    }

    _allContacts = list;
    _filteredContacts = list;
  }

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filteredContacts = _allContacts);
      return;
    }

    setState(() {
      _filteredContacts = _allContacts.where((c) {
        final matchesName = c.displayName.toLowerCase().contains(q);
        final matchesPhone = c.cleanPhone.contains(q) || c.rawPhone.contains(q);
        return matchesName || matchesPhone;
      }).toList();
    });
  }

  void _onManualPhoneChanged(String val) {
    final cleaned = _cleanTo10Digits(val);
    if (cleaned.length >= 10) {
      final match = _registeredUsers.cast<StoredUserAccount?>().firstWhere(
        (a) => a != null && _cleanTo10Digits(a.phone) == cleaned,
        orElse: () => null,
      );
      if (match != null) {
        setState(() {
          _detectedManualAppUser = match;
          if (_nameController.text.trim().isEmpty) {
            _nameController.text = match.name;
          }
        });
        return;
      }
    }
    if (_detectedManualAppUser != null) {
      setState(() => _detectedManualAppUser = null);
    }
  }

  Future<void> _addFriendDirectly({
    required String phone,
    required String name,
    required bool isAppUser,
  }) async {
    final clean = _cleanTo10Digits(phone);
    if (clean.length < 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid phone number'),
            backgroundColor: context.colors.accentOwe,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(friendsNotifierProvider.notifier).addFriend(
            phone: clean,
            name: name,
            contactName: name,
            isAppUser: isAppUser,
          );

      // Update local sets
      _existingFriendPhoneSet.add(clean);

      // Update contacts list state in place
      setState(() {
        _allContacts = _allContacts.map((c) {
          if (c.cleanPhone == clean) {
            return ContactEntry(
              id: c.id,
              displayName: c.displayName,
              rawPhone: c.rawPhone,
              cleanPhone: c.cleanPhone,
              isAppUser: c.isAppUser,
              isAlreadyFriend: true,
            );
          }
          return c;
        }).toList();
        _filteredContacts = _filteredContacts.map((c) {
          if (c.cleanPhone == clean) {
            return ContactEntry(
              id: c.id,
              displayName: c.displayName,
              rawPhone: c.rawPhone,
              cleanPhone: c.cleanPhone,
              isAppUser: c.isAppUser,
              isAlreadyFriend: true,
            );
          }
          return c;
        }).toList();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $name directly as SplitUp friend!'),
          backgroundColor: context.colors.accentReceive,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: context.colors.accentOwe,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addAndInviteViaSms({
    required String phone,
    required String name,
  }) async {
    final clean = _cleanTo10Digits(phone);
    setState(() => _isLoading = true);

    try {
      // 1. Add to local friend ledger so expenses can be tracked immediately
      await ref.read(friendsNotifierProvider.notifier).addFriend(
            phone: clean,
            name: name,
            contactName: name,
            isAppUser: false,
          );

      _existingFriendPhoneSet.add(clean);

      setState(() {
        _allContacts = _allContacts.map((c) {
          if (c.cleanPhone == clean) {
            return ContactEntry(
              id: c.id,
              displayName: c.displayName,
              rawPhone: c.rawPhone,
              cleanPhone: c.cleanPhone,
              isAppUser: c.isAppUser,
              isAlreadyFriend: true,
            );
          }
          return c;
        }).toList();
        _filteredContacts = _filteredContacts.map((c) {
          if (c.cleanPhone == clean) {
            return ContactEntry(
              id: c.id,
              displayName: c.displayName,
              rawPhone: c.rawPhone,
              cleanPhone: c.cleanPhone,
              isAppUser: c.isAppUser,
              isAlreadyFriend: true,
            );
          }
          return c;
        }).toList();
      });

      if (!mounted) return;

      // 2. Launch SMS App
      final message = 'Hey $name! I added you on SplitUp to track our shared expenses. Download the app here: https://split-up-two.vercel.app';
      final smsUri = Uri(
        scheme: 'sms',
        path: '+91$clean',
        queryParameters: <String, String>{'body': message},
      );

      try {
        await launchUrl(smsUri);
      } catch (_) {
        final fallback = Uri.parse('sms:+91$clean?body=${Uri.encodeComponent(message)}');
        if (await canLaunchUrl(fallback)) {
          await launchUrl(fallback);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $name to ledger & opening SMS app!'),
          backgroundColor: context.colors.accentReceive,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: context.colors.accentOwe,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final screenHeight = MediaQuery.of(context).size.height;

    return GlassSheet(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.90,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.accentReceive.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.person_add_rounded, color: colors.accentReceive, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Friends',
                          style: SplitUpTypography.headline(color: colors.textPrimary).copyWith(fontSize: 20),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'From your phone contacts or mobile number',
                          style: SplitUpTypography.caption(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: colors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Segmented Tabs: [Phone Contacts] vs [Enter Manually]
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colors.surfaceFlatRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.divider),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedTab == 0 ? colors.accentReceive : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.contacts_rounded,
                                  size: 16,
                                  color: _selectedTab == 0 ? Colors.white : colors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Phone Contacts',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: _selectedTab == 0 ? Colors.white : colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedTab == 1 ? colors.accentReceive : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.edit_note_rounded,
                                  size: 17,
                                  color: _selectedTab == 1 ? Colors.white : colors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Enter Manually',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: _selectedTab == 1 ? Colors.white : colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // TAB CONTENT
              Expanded(
                child: _selectedTab == 0 ? _buildContactsView(colors) : _buildManualView(colors),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: PHONE CONTACTS VIEW
  // -------------------------------------------------------------
  Widget _buildContactsView(dynamic colors) {
    if (_isLoadingContacts) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colors.accentReceive),
            const SizedBox(height: 14),
            Text('Reading contacts...', style: SplitUpTypography.body(color: colors.textSecondary)),
          ],
        ),
      );
    }

    if (_permissionGranted == false) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.accentOwe.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.no_accounts_rounded, size: 40, color: colors.accentOwe),
              ),
              const SizedBox(height: 16),
              Text(
                'Contacts Permission Required',
                style: SplitUpTypography.title(color: colors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Allow SplitUp to read your phone contacts to quickly split expenses with friends without typing phone numbers.',
                textAlign: TextAlign.center,
                style: SplitUpTypography.body(color: colors.textSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.accentReceive,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text('Allow Contacts Access'),
                onPressed: _requestAndLoadContacts,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Search Contacts Box + Quick Native Contact Picker
        Row(
          children: [
            Expanded(
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: colors.textMuted, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: SplitUpTypography.body(color: colors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search name or mobile number...',
                          hintStyle: SplitUpTypography.body(color: colors.textMuted),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        color: colors.textMuted,
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
                  ],
                ),
              ),
            ),
            if (!kIsWeb) ...[
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: colors.surfaceFlatRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colors.divider),
                  ),
                ),
                tooltip: 'Select single contact from phonebook',
                icon: Icon(Icons.perm_contact_calendar_rounded, color: colors.accentReceive, size: 20),
                onPressed: _pickNativeContact,
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Contacts List
        Expanded(
          child: _filteredContacts.isEmpty
              ? Center(
                  child: Text(
                    _searchController.text.isEmpty
                        ? 'No contacts found on device'
                        : 'No contacts match "${_searchController.text}"',
                    style: SplitUpTypography.caption(color: colors.textMuted),
                  ),
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: _filteredContacts.length,
                  separatorBuilder: (_, _) => Divider(color: colors.divider, height: 1),
                  itemBuilder: (context, index) {
                    final item = _filteredContacts[index];
                    return _buildContactTile(item, colors);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildContactTile(ContactEntry item, dynamic colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Avatar
          Avatar(name: item.displayName, size: 40),
          const SizedBox(width: 12),

          // Name & Phone
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                      ),
                    ),
                    if (item.isAppUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.accentReceive.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colors.accentReceive.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 11, color: colors.accentReceive),
                            const SizedBox(width: 3),
                            Text(
                              'On SplitUp',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: colors.accentReceive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '+91 ${item.cleanPhone}',
                  style: SplitUpTypography.caption(color: colors.textMuted),
                ),
              ],
            ),
          ),

          // Action Button
          if (item.isAlreadyFriend)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: colors.surfaceFlatRaised,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.done_all_rounded, size: 14, color: colors.accentReceive),
                  const SizedBox(width: 4),
                  Text(
                    'Added',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else if (item.isAppUser)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.accentReceive,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                elevation: 0,
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
              label: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              onPressed: _isLoading
                  ? null
                  : () => _addFriendDirectly(
                        phone: item.cleanPhone,
                        name: item.displayName,
                        isAppUser: true,
                      ),
            )
          else
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.accentReceive,
                side: BorderSide(color: colors.accentReceive.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              icon: const Icon(Icons.sms_rounded, size: 14),
              label: const Text('Invite', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              onPressed: _isLoading
                  ? null
                  : () => _addAndInviteViaSms(
                        phone: item.cleanPhone,
                        name: item.displayName,
                      ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: MANUAL ENTRY VIEW
  // -------------------------------------------------------------
  Widget _buildManualView(dynamic colors) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mobile Number Field
          Text(
            'Mobile Number *',
            style: SplitUpTypography.label(color: colors.textSecondary),
          ),
          const SizedBox(height: 6),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Text(
                  '🇮🇳 +91',
                  style: SplitUpTypography.title(color: colors.textPrimary),
                ),
                const SizedBox(width: 10),
                Container(width: 1, height: 24, color: colors.divider),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    onChanged: _onManualPhoneChanged,
                    style: SplitUpTypography.title(color: colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: '10-digit mobile number',
                      hintStyle: SplitUpTypography.title(color: colors.textMuted),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Live App User Detection Badge
          if (_detectedManualAppUser != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.accentReceive.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.accentReceive.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_rounded, size: 16, color: colors.accentReceive),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SplitUp Member: ${_detectedManualAppUser!.name}',
                      style: SplitUpTypography.caption(color: colors.accentReceive).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 14),

          // Friend Name Field
          Text(
            "Friend's Name *",
            style: SplitUpTypography.label(color: colors.textSecondary),
          ),
          const SizedBox(height: 6),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: SplitUpTypography.title(color: colors.textPrimary),
              decoration: InputDecoration(
                icon: Icon(Icons.person_outline_rounded, color: colors.textMuted, size: 20),
                hintText: 'e.g. Aditi Sharma, Rohan',
                hintStyle: SplitUpTypography.title(color: colors.textMuted),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Add Button
          PrimaryButton(
            label: _detectedManualAppUser != null ? 'Add Directly' : 'Add & Send SMS Invite',
            icon: _detectedManualAppUser != null ? Icons.person_add_rounded : Icons.sms_rounded,
            isLoading: _isLoading,
            onPressed: () {
              final phone = _phoneController.text.trim();
              final name = _nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text("Please enter your friend's name"),
                    backgroundColor: colors.accentOwe,
                  ),
                );
                return;
              }

              if (_detectedManualAppUser != null) {
                _addFriendDirectly(phone: phone, name: name, isAppUser: true);
              } else {
                _addAndInviteViaSms(phone: phone, name: name);
              }
            },
          ),
        ],
      ),
    );
  }
}
