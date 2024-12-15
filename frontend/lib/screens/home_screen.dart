import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = FlutterSecureStorage();
  IO.Socket? socket;
  String? _userToken;
  String? _currentUserId;
  List<Map<String, dynamic>> userList = [];
  List<Map<String, dynamic>> filteredList = [];
  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserToken();
    _connectSocket();
    searchController.addListener(_filterUsers);
  }

  Future<void> _loadUserToken() async {
    final token = await _storage.read(key: 'token');
    if (token == null) {
      Navigator.pushReplacementNamed(context, '/');
    } else {
      setState(() {
        _userToken = token;
        _currentUserId = _decodeToken(token)['id'];
      });
    }
  }

  Map<String, dynamic> _decodeToken(String token) {
    final parts = token.split('.');
    return json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
  }

  // Fetch users based on the search query (email)
  Future<void> _fetchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        filteredList = [];
      });
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('http://192.168.1.11:5000/users'),
        headers: {
          'Authorization': 'Bearer $_userToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List users = json.decode(response.body);
        setState(() {
          userList = users.cast<Map<String, dynamic>>();
          // Filter users by the query entered
          filteredList = userList
              .where((user) => user['email'].toString().toLowerCase().contains(query.toLowerCase()))
              .toList();
        });
        _fetchLatestMessages();
      } else {
        print('Failed to load users: ${response.body}');
      }
    } catch (e) {
      print('Error fetching users: $e');
    }
  }

  // Fetch the latest message for each user
  Future<void> _fetchLatestMessages() async {
    try {
      for (var user in filteredList) {
        final response = await http.get(
          Uri.parse('http://192.168.1.11:5000/chatHistory/$_currentUserId/${user['_id']}'),
          headers: {
            'Authorization': 'Bearer $_userToken',
            'Content-Type': 'application/json',
          },
        );
        if (response.statusCode == 200) {
          final List messages = json.decode(response.body);
          if (messages.isNotEmpty) {
            setState(() {
              user['latestMessage'] = messages[0]['message'];  // Store the latest message
              user['timestamp'] = messages[0]['timestamp'];    // Store the timestamp of the latest message
            });
          } else {
            setState(() {
              user['latestMessage'] = 'No messages yet';  // No messages yet
            });
          }
        }
      }
    } catch (e) {
      print('Error fetching latest messages: $e');
    }
  }

  void _connectSocket() {
    socket = IO.io('http://192.168.1.11:5000', {
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket?.connect();

    socket?.on('connect', (_) {
      print('Connected to socket server');
      if (_currentUserId != null) {
        socket?.emit('userLoggedIn', _currentUserId);
      }
    });
  }

  void _filterUsers() {
    final query = searchController.text;
    _fetchUsers(query);
  }

  void _startChat(String receiverId, String receiverUsername) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          senderId: _currentUserId!,
          receiverId: receiverId,
          receiverUsername: receiverUsername,  // Pass the username here
          socket: socket,
        ),
      ),
    );
  }

  @override
  void dispose() {
    socket?.disconnect();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat App", style: TextStyle(
            fontSize: 18,
            color: Colors.white,
            fontWeight: FontWeight.bold)),
        backgroundColor: Color(0xFF0084FF), // Messenger Blue
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00B0FF), Colors.redAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(15.0),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: 'Search by email',
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.search, color: Colors.black),
                ),
              ),
            ),
            Expanded(
              child: filteredList.isEmpty
                  ? const Center(
                child: Text(
                  "No users found",
                  style: TextStyle(fontSize: 18, color: Colors.white70),
                ),
              )
                  : ListView.builder(
                itemCount: filteredList.length,
                itemBuilder: (context, index) {
                  final user = filteredList[index];
                  return _buildUserCard(user);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 15.0),
      color: Colors.white.withOpacity(0.3), // Transparent background
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 15.0),
        title: Text(
          user['email'],
          style: const TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          user['latestMessage'] ?? 'Tap to chat', // Display latest message
          style: const TextStyle(color: Colors.white70),
        ),
        leading: CircleAvatar(
          backgroundColor: Colors.white,
          child: Text(
            user['email'][0].toUpperCase(),
            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
          ),
        ),
        onTap: () {
          _startChat(user['_id'], user['email']);  // Pass username (email here)
        },
      ),
    );
  }
}
