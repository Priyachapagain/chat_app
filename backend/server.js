const express = require('express');
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const bodyParser = require('body-parser');
const cors = require('cors');
const socketIo = require('socket.io');
const http = require('http');
require('dotenv').config();

const app = express();
const server = http.createServer(app);
const io = socketIo(server);

app.use(cors());
app.use(bodyParser.json());

const PORT = process.env.PORT || 5000;
const MONGO_URI = process.env.MONGO_URI;
const JWT_SECRET = process.env.JWT_SECRET;

mongoose.connect(MONGO_URI, { useNewUrlParser: true, useUnifiedTopology: true });

// User Schema 
const UserSchema = new mongoose.Schema({
  email: { type: String, required: true, unique: true },
  password: { type: String, required: true },
  username: { type: String, required: true, unique: true },  // New username field
});
const User = mongoose.model('User', UserSchema);

// Message Schema
const MessageSchema = new mongoose.Schema({
  senderId: { type: String, required: true },
  receiverId: { type: String, required: true },
  message: { type: String, required: true },
  timestamp: { type: Date, default: Date.now },
});
const Message = mongoose.model('Message', MessageSchema);

// User registration 
app.post('/register', async (req, res) => {
  const { email, password, username } = req.body;

  const existingUser = await User.findOne({ $or: [{ email }, { username }] });
  if (existingUser) {
    return res.status(400).json({ error: 'Email or username already exists' });
  }

  const hashedPassword = await bcrypt.hash(password, 10);
  const newUser = new User({ email, password: hashedPassword, username });

  try {
    await newUser.save();
    res.status(201).json({ message: 'User registered successfully' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to register user' });
  }
});

// User login
app.post('/login', async (req, res) => {
  const { email, password } = req.body;
  const user = await User.findOne({ email });
  if (!user) return res.status(404).json({ error: 'User not found' });
  if (!(await bcrypt.compare(password, user.password)))
    return res.status(400).json({ error: 'Invalid credentials' });
  const token = jwt.sign({ id: user._id }, JWT_SECRET, { expiresIn: '1h' });
  res.json({ token });
});

// Get all users
app.get('/users', async (req, res) => {
  const users = await User.find({});
  res.json(users);
});

// Get chat history with pagination
// Get chat history between sender and receiver
app.get('/chatHistory/:senderId/:receiverId', async (req, res) => {
  const { senderId, receiverId } = req.params;
  const page = parseInt(req.query.page) || 1;
  const limit = 20; // Messages per page

  try {
    const messages = await Message.find({
      $or: [
        { senderId, receiverId },
        { senderId: receiverId, receiverId: senderId },
      ],
    })
      .sort({ timestamp: -1 }) // Most recent messages first
      .skip((page - 1) * limit)
      .limit(limit);

    res.json(messages);
  } catch (err) {
    console.error('Error fetching messages:', err);
    res.status(500).json({ error: 'Failed to fetch messages' });
  }
});

// Socket.io
io.on('connection', (socket) => {
  console.log('New client connected');

  socket.on('sendMessage', async (data) => {
    const { senderId, receiverId, message, timestamp } = data;
    const newMessage = new Message({ senderId, receiverId, message, timestamp });
    await newMessage.save();
    io.to(receiverId).emit('receiveMessage', data);
  });

  socket.on('disconnect', () => {
    console.log('Client disconnected');
  });
});

// In your backend (Node.js with MongoDB)
app.get('/chatHistory/:senderId/:receiverId', async (req, res) => {
  const { senderId, receiverId } = req.params;

  try {
    const messages = await Message.find({
      $or: [
        { sender: senderId, receiver: receiverId },
        { sender: receiverId, receiver: senderId }
      ]
    }).sort({ timestamp: -1 }).limit(1); // Fetch the latest message

    if (messages.length > 0) {
      res.status(200).json(messages);
    } else {
      res.status(200).json([]); // No messages yet
    }
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch messages' });
  }
});


server.listen(PORT, () => console.log(`Server running on port ${PORT}`));
