const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { PrismaClient } = require('@prisma/client');
const authMiddleware = require('./authMiddleware');
const multer = require('multer');
const path = require('path');
const userConnections = new Map();
const nodemailer = require('nodemailer');
const app = express();
const server = http.createServer(app);
const io = new Server(server);
const prisma = new PrismaClient();
const PORT = 3000;

app.use(express.json());

// Разрешаем доступ к папке uploads напрямую по ссылке (чтобы отдавать файлы)
app.use('/uploads', express.static('uploads'));

// Настройка multer - куда и как сохранять загружаемые файлы
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, 'uploads/avatars');
  },
  filename: (req, file, cb) => {
    // Уникальное имя файла: userId + время + оригинальное расширение
    const uniqueName = `${req.userId}-${Date.now()}${path.extname(file.originalname)}`;
    cb(null, uniqueName);
  },
});

const upload = multer({
  storage: storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowedExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
    const ext = path.extname(file.originalname).toLowerCase();

    if (file.mimetype.startsWith('image/') || allowedExtensions.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error('Разрешены только изображения (jpg, png, webp, gif)'));
    }
  },
});

const emailTransporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASSWORD,
  },
});

function generateVerificationCode() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// Настройка multer для файлов чата (фото и документы)
const chatFileStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, 'uploads/chat_files');
  },
  filename: (req, file, cb) => {
    const uniqueName = `${Date.now()}-${Math.round(Math.random() * 1e9)}${path.extname(file.originalname)}`;
    cb(null, uniqueName);
  },
});

const uploadChatFile = multer({
  storage: chatFileStorage,
  limits: { fileSize: 20 * 1024 * 1024 },
});

app.get('/', (req, res) => {
  res.send('Привет! Сервер мессенджера работает.');
});


function isValidUsername(username) {
  const regex = /^[a-zA-Z_][a-zA-Z0-9_]{4,31}$/;
  return regex.test(username);
}

const allowedEmailDomains = [
  'gmail.com',
  'mail.ru',
  'yandex.ru',
  'yandex.com',
  'outlook.com',
  'hotmail.com',
  'icloud.com',
  'yahoo.com',
  'bk.ru',
  'inbox.ru',
  'list.ru',
  'rambler.ru',
  'protonmail.com',
];

function isAllowedEmailDomain(email) {
  const domain = email.split('@')[1]?.toLowerCase();
  return allowedEmailDomains.includes(domain);
}

// Этап 1: запрос регистрации - проверка данных и отправка кода на email
app.post('/register/request', async (req, res) => {
  try {
    const { name, username, email, password } = req.body;

    if (!name || !username || !email || !password) {
      return res.status(400).json({ error: 'Заполните все поля' });
    }

    if (!isAllowedEmailDomain(email)) {
      return res.status(400).json({
        error: 'Используйте существующий домен',
      });
    }

    if (!isValidUsername(username)) {
      return res.status(400).json({
        error: 'Никнейм должен быть 5-32 символа, латинские буквы, цифры и _, не начинаться с цифры',
      });
    }

    const usernameLower = username.toLowerCase();

    const existingUsername = await prisma.user.findUnique({ where: { username: usernameLower } });
    if (existingUsername) {
      return res.status(400).json({ error: 'Этот никнейм уже занят' });
    }

    const existingEmail = await prisma.user.findUnique({ where: { email } });
    if (existingEmail) {
      return res.status(400).json({ error: 'Этот email уже зарегистрирован' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const code = generateVerificationCode();

    // Удаляем предыдущую незавершённую попытку регистрации с этим email, если была
    await prisma.pendingRegistration.deleteMany({ where: { email } });

    await prisma.pendingRegistration.create({
      data: {
        name,
        username: usernameLower,
        email,
        password: hashedPassword,
        code,
      },
    });

    await emailTransporter.sendMail({
      from: process.env.EMAIL_USER,
      to: email,
      subject: 'Код подтверждения NIT',
      text: `Ваш код подтверждения: ${code}\n\nЕсли вы не запрашивали регистрацию, просто проигнорируйте это письмо.`,
    });

    res.json({ success: true, message: 'Код отправлен на почту' });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

app.post('/register/verify', async (req, res) => {
  try {
    const { email, code } = req.body;

    if (!email || !code) {
      return res.status(400).json({ error: 'Заполните все поля' });
    }

    const pending = await prisma.pendingRegistration.findUnique({ where: { email } });

    if (!pending) {
      return res.status(400).json({ error: 'Запрос на регистрацию не найден. Попробуйте снова' });
    }

    if (pending.code !== code) {
      return res.status(400).json({ error: 'Неверный код' });
    }

    const user = await prisma.user.create({
      data: {
        name: pending.name,
        username: pending.username,
        email: pending.email,
        password: pending.password,
      },
    });

    await prisma.pendingRegistration.delete({ where: { email } });

    res.status(201).json({
      id: user.id,
      name: user.name,
      username: user.username,
      email: user.email,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Маршрут входа
app.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'Заполните все поля' });
    }

    // Ищем пользователя по email
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      return res.status(400).json({ error: 'Неверный email или пароль' });
    }

    // Сравниваем введённый пароль с хешем в базе
    const passwordMatches = await bcrypt.compare(password, user.password);
    if (!passwordMatches) {
      return res.status(400).json({ error: 'Неверный email или пароль' });
    }

    // Создаём JWT токен, "зашивая" в него id пользователя
    const token = jwt.sign(
      { userId: user.id },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.json({
      token,
      user: {
        id: user.id,
        name: user.name,
        username: user.username,
        email: user.email,
      },
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Поиск пользователя по username (защищённый маршрут)
app.get('/users/search/:username', authMiddleware, async (req, res) => {
  try {
    const { username } = req.params;
    const usernameLower = username.toLowerCase();

    const user = await prisma.user.findUnique({
      where: { username: usernameLower },
      select: {
        id: true,
        name: true,
        username: true,
        avatarUrl: true,
      },
    });

    if (!user) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }

    res.json(user);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Получить публичные данные любого пользователя по id
app.get('/users/:userId', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.params;

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        name: true,
        username: true,
        status: true,
        avatarUrl: true,
        isOnline: true,
        lastSeen: true,
      },
    });

    if (!user) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }

    res.json(user);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Создать чат с пользователем (или вернуть существующий)
app.post('/chats', authMiddleware, async (req, res) => {
  try {
    const { userId: otherUserId } = req.body;
    const myUserId = req.userId;

    if (!otherUserId) {
      return res.status(400).json({ error: 'Не указан пользователь' });
    }

    if (otherUserId === myUserId) {
      return res.status(400).json({ error: 'Нельзя создать чат с самим собой' });
    }

    // Проверяем, существует ли уже чат между этими двумя людьми (в любом порядке)
    let chat = await prisma.chat.findFirst({
      where: {
        OR: [
          { participantOneId: myUserId, participantTwoId: otherUserId },
          { participantOneId: otherUserId, participantTwoId: myUserId },
        ],
      },
    });

    // Если чата ещё нет - создаём новый
    if (!chat) {
      chat = await prisma.chat.create({
        data: {
          participantOneId: myUserId,
          participantTwoId: otherUserId,
        },
      });
    }

    res.status(201).json(chat);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Получить список моих чатов
app.get('/chats', authMiddleware, async (req, res) => {
  try {
    const myUserId = req.userId;

    const chats = await prisma.chat.findMany({
      where: {
        OR: [
          { participantOneId: myUserId },
          { participantTwoId: myUserId },
        ],
      },
      include: {
        participantOne: { select: { id: true, name: true, username: true, avatarUrl: true, isOnline: true, lastSeen: true } },
        participantTwo: { select: { id: true, name: true, username: true, avatarUrl: true, isOnline: true, lastSeen: true } },
        messages: {
          orderBy: { createdAt: 'desc' },
          take: 1,
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    const formattedChats = await Promise.all(
      chats.map(async (chat) => {
        const isParticipantOne = chat.participantOneId === myUserId;
        const otherUser = isParticipantOne ? chat.participantTwo : chat.participantOne;
        const myLastReadAt = isParticipantOne
          ? chat.participantOneLastReadAt
          : chat.participantTwoLastReadAt;

        const unreadCount = await prisma.message.count({
          where: {
            chatId: chat.id,
            senderId: { not: myUserId },
            createdAt: myLastReadAt ? { gt: myLastReadAt } : undefined,
          },
        });

        return {
          id: chat.id,
          otherUser,
          lastMessage: chat.messages[0] || null,
          unreadCount,
          createdAt: chat.createdAt,
        };
      })
    );

    res.json(formattedChats);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Получить сообщения конкретного чата
app.get('/chats/:chatId/messages', authMiddleware, async (req, res) => {
  try {
    const { chatId } = req.params;
    const myUserId = req.userId;
    const limit = parseInt(req.query.limit) || 30;
    const before = req.query.before; // id сообщения, ДО которого грузим (для пагинации назад)

    const chat = await prisma.chat.findUnique({ where: { id: chatId } });
    if (!chat) {
      return res.status(404).json({ error: 'Чат не найден' });
    }

    const whereClause = { chatId };
    if (before) {
      const beforeMessage = await prisma.message.findUnique({ where: { id: before } });
      if (beforeMessage) {
        whereClause.createdAt = { lt: beforeMessage.createdAt };
      }
    }

    const messages = await prisma.message.findMany({
      where: whereClause,
      include: {
        sender: { select: { id: true, name: true, username: true, avatarUrl: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: limit,
    });

    const myLastReadAt =
      chat.participantOneId === myUserId
        ? chat.participantOneLastReadAt
        : chat.participantTwoLastReadAt;

    const otherUserLastReadAt =
      chat.participantOneId === myUserId
        ? chat.participantTwoLastReadAt
        : chat.participantOneLastReadAt;

    const orderedMessages = messages.reverse();

    res.json({
      messages: orderedMessages,
      lastReadAt: myLastReadAt,
      otherUserLastReadAt,
      hasMore: messages.length === limit,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Отправить сообщение в чат
app.post('/chats/:chatId/messages', authMiddleware, async (req, res) => {
  try {
    const { chatId } = req.params;
    const { text, type, fileUrl, fileName } = req.body;
    const senderId = req.userId;

    const messageType = type || 'text';

    if (messageType === 'text' && (!text || text.trim().length === 0)) {
      return res.status(400).json({ error: 'Сообщение не может быть пустым' });
    }

    const message = await prisma.message.create({
      data: {
        text: text ? text.trim() : null,
        type: messageType,
        fileUrl: fileUrl || null,
        fileName: fileName || null,
        chatId,
        senderId,
      },
      include: {
        sender: { select: { id: true, name: true, username: true, avatarUrl: true } },
      },
    });

    const chat = await prisma.chat.findUnique({ where: { id: chatId } });

    io.to(chatId).emit('newMessage', message);
    io.to(`user_${chat.participantOneId}`).emit('chatListUpdate');
    io.to(`user_${chat.participantTwoId}`).emit('chatListUpdate');

    // Определяем получателя и проверяем, онлайн ли он - если да, считаем доставленным сразу
    const recipientId =
      chat.participantOneId === senderId ? chat.participantTwoId : chat.participantOneId;
    const recipient = await prisma.user.findUnique({ where: { id: recipientId } });

    if (recipient && recipient.isOnline) {
      await prisma.message.update({
        where: { id: message.id },
        data: { delivered: true },
      });
      io.to(`user_${senderId}`).emit('messageDelivered', {
        chatId,
        messageId: message.id,
      });
    }

    res.status(201).json(message);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

app.post('/chats/:chatId/read', authMiddleware, async (req, res) => {
  try {
    const { chatId } = req.params;
    const myUserId = req.userId;

    const chat = await prisma.chat.findUnique({ where: { id: chatId } });
    if (!chat) {
      return res.status(404).json({ error: 'Чат не найден' });
    }

    const isParticipantOne = chat.participantOneId === myUserId;
    const otherUserId = isParticipantOne ? chat.participantTwoId : chat.participantOneId;

    await prisma.chat.update({
      where: { id: chatId },
      data: isParticipantOne
        ? { participantOneLastReadAt: new Date() }
        : { participantTwoLastReadAt: new Date() },
    });

    // Уведомляем комнату чата, что сообщения прочитаны
    io.to(chatId).emit('messagesRead', { chatId, readByUserId: myUserId });

    res.json({ success: true });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Получить данные текущего пользователя
app.get('/me', authMiddleware, async (req, res) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.userId },
      select: {
        id: true,
        name: true,
        username: true,
        email: true,
        status: true,
        avatarUrl: true,
        createdAt: true,
      },
    });

    if (!user) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }

    res.json(user);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Обновить свои данные (имя, username, статус)
app.patch('/me', authMiddleware, async (req, res) => {
  try {
    const { name, username, status } = req.body;
    const dataToUpdate = {};

    if (name !== undefined) {
      if (name.trim().length === 0) {
        return res.status(400).json({ error: 'Имя не может быть пустым' });
      }
      dataToUpdate.name = name.trim();
    }

    if (username !== undefined) {
      if (!isValidUsername(username)) {
        return res.status(400).json({
          error: 'Никнейм должен быть 5-32 символа, латинские буквы, цифры и _, не начинаться с цифры',
        });
      }

      const usernameLower = username.toLowerCase();

      const existingUsername = await prisma.user.findUnique({
        where: { username: usernameLower },
      });

      if (existingUsername && existingUsername.id !== req.userId) {
        return res.status(400).json({ error: 'Этот никнейм уже занят' });
      }

      dataToUpdate.username = usernameLower;
    }

    if (status !== undefined) {
      dataToUpdate.status = status.trim();
    }

    const user = await prisma.user.update({
      where: { id: req.userId },
      data: dataToUpdate,
      select: {
        id: true,
        name: true,
        username: true,
        email: true,
        status: true,
        avatarUrl: true,
      },
    });

    res.json(user);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Загрузить аватар
app.post('/me/avatar', authMiddleware, (req, res, next) => {
  upload.single('avatar')(req, res, (err) => {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    next();
  });
}, async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Файл не был загружен' });
    }

    const avatarUrl = `/uploads/avatars/${req.file.filename}`;

    const user = await prisma.user.update({
      where: { id: req.userId },
      data: { avatarUrl },
      select: {
        id: true,
        name: true,
        username: true,
        email: true,
        status: true,
        avatarUrl: true,
      },
    });

    res.json(user);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// Загрузить файл (изображение или документ) для отправки в чат
app.post('/upload/chat-file', authMiddleware, (req, res, next) => {
  uploadChatFile.single('file')(req, res, (err) => {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    next();
  });
}, async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Файл не был загружен' });
    }

    const fileUrl = `/uploads/chat_files/${req.file.filename}`;
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
    const ext = path.extname(req.file.originalname).toLowerCase();
    const isImage = req.file.mimetype.startsWith('image/') || imageExtensions.includes(ext);

    res.json({
      fileUrl,
      fileName: Buffer.from(req.file.originalname, 'latin1').toString('utf8'),
      type: isImage ? 'image' : 'file',
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

io.on('connection', (socket) => {
  console.log('Пользователь подключился:', socket.id);

  socket.on('identify', async (userId) => {
    socket.userId = userId;
    socket.join(`user_${userId}`); // персональная комната пользователя

    const currentCount = userConnections.get(userId) || 0;
    userConnections.set(userId, currentCount + 1);

    if (currentCount === 0) {
      try {
        await prisma.user.update({
          where: { id: userId },
          data: { isOnline: true },
        });
        io.emit('userStatusChanged', { userId, isOnline: true });
      } catch (error) {
        console.error('Ошибка при обновлении статуса на онлайн:', error);
      }
    }

    // Находим все чужие недоставленные сообщения, адресованные этому пользователю,
    // и уведомляем их отправителей о доставке
    try {
      const undeliveredMessages = await prisma.message.findMany({
        where: {
          delivered: false,
          senderId: { not: userId },
          chat: {
            OR: [
              { participantOneId: userId },
              { participantTwoId: userId },
            ],
          },
        },
      });

      for (const msg of undeliveredMessages) {
        await prisma.message.update({
          where: { id: msg.id },
          data: { delivered: true },
        });
        io.to(`user_${msg.senderId}`).emit('messageDelivered', {
          chatId: msg.chatId,
          messageId: msg.id,
        });
      }
    } catch (error) {
      console.error('Ошибка при обработке недоставленных сообщений:', error);
    }
  });

  socket.on('joinChat', (chatId) => {
    socket.join(chatId);
    console.log(`Сокет ${socket.id} присоединился к чату ${chatId}`);
  });

  socket.on('leaveChat', (chatId) => {
    socket.leave(chatId);
    console.log(`Сокет ${socket.id} покинул чат ${chatId}`);
  });

  socket.on('typing', (data) => {
    socket.to(data.chatId).emit('userTyping', { userId: data.userId });
  });

  socket.on('disconnect', async () => {
    console.log('Пользователь отключился:', socket.id);

    if (socket.userId) {
      const currentCount = userConnections.get(socket.userId) || 0;
      const newCount = Math.max(0, currentCount - 1);
      userConnections.set(socket.userId, newCount);

      if (newCount === 0) {
        try {
          const updatedUser = await prisma.user.update({
            where: { id: socket.userId },
            data: { isOnline: false, lastSeen: new Date() },
          });

          io.emit('userStatusChanged', {
            userId: socket.userId,
            isOnline: false,
            lastSeen: updatedUser.lastSeen,
          });
        } catch (error) {
          console.error('Ошибка при обновлении статуса на оффлайн:', error);
        }
      }
    }
  });
});

server.listen(PORT, () => {
  console.log(`Сервер запущен на http://localhost:${PORT}`);
});
