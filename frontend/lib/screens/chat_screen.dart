import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';



import 'dart:convert';

class ChatScreen extends StatefulWidget {
  final String senderId;
  final String receiverId;
  final String receiverUsername; // Added receiver's username for better UI
  final IO.Socket? socket;

  const ChatScreen({
    super.key,
    required this.senderId,
    required this.receiverId,
    required this.receiverUsername,
    required this.socket,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> messages = [];
  final FlutterSecureStorage _storage = FlutterSecureStorage();
  bool isLoadingMore = false;
  bool isLoading = false;
  int currentPage = 1;

  @override
  void initState() {
    super.initState();

    // Listen for new messages
    widget.socket?.on('receiveMessage', (data) {
      setState(() {
        messages.insert(0, {
          'message': data['message'],
          'senderId': data['senderId'],
          'timestamp': data['timestamp'],
        });
      });
    });

    // Load chat history
    _loadChatHistory();

    // Add scroll listener for pagination
    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
          _scrollController.position.maxScrollExtent &&
          !isLoadingMore) {
        _loadMoreMessages();
      }
    });
  }

  Future<void> _loadChatHistory() async {
    setState(() {
      isLoading = true;
    });

    try {
      final token = await _storage.read(key: 'token'); // Fetch JWT token
      final response = await http.get(
        Uri.parse(
            'http://192.168.1.11:5000/chatHistory/${widget.senderId}/${widget.receiverId}?page=$currentPage'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          messages.addAll(data.map((msg) {
            return {
              'message': msg['message'],
              'senderId': msg['senderId'],
              'timestamp': msg['timestamp'],
            };
          }).toList());
        });
      }
    } catch (e) {
      print('Error loading chat history: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadMoreMessages() async {
    if (isLoadingMore) return;

    setState(() {
      isLoadingMore = true;
    });

    currentPage++;
    await _loadChatHistory();

    setState(() {
      isLoadingMore = false;
    });
  }

  void _sendMessage() {
    final message = _controller.text.trim();
    if (message.isNotEmpty) {
      final timestamp = DateTime.now().toIso8601String();
      widget.socket?.emit('sendMessage', {
        'senderId': widget.senderId,
        'receiverId': widget.receiverId,
        'message': message,
        'timestamp': timestamp,
      });

      setState(() {
        messages.insert(0, {
          'message': message,
          'senderId': widget.senderId,
          'timestamp': timestamp,
        });
      });

      _controller.clear();
    }
  }

  Future<void> _logout() async {
    await _storage.delete(key: 'token'); // Remove token
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false); // Navigate to login
  }

  @override
  void dispose() {
    widget.socket?.off('receiveMessage');
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.receiverUsername, style: TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),), // Display username
        backgroundColor: Color(0xFF0084FF), // Messenger Blue
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _logout, // Logout functionality
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00B0FF), Color(0xFF0084FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            if (isLoading)
              const LinearProgressIndicator(), // Show loading indicator for the initial load
            Expanded(
              child: ListView.builder(
                reverse: true,
                controller: _scrollController,
                itemCount: messages.length + (isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (isLoadingMore && index == messages.length) {
                    return const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final message = messages[index];
                  final isSentByMe = message['senderId'] == widget.senderId;

                  return Align(
                    alignment: isSentByMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          vertical: 5, horizontal: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSentByMe
                            ? Colors.blue[100]
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message['message'],
                            style: TextStyle(fontSize: 16),
                          ),
                          SizedBox(height: 5),
                          Text(
                            DateFormat('hh:mm a').format(
                              DateTime.parse(message['timestamp']),
                            ),
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
