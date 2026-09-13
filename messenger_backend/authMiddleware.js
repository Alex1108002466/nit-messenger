const jwt = require('jsonwebtoken');

function authMiddleware(req, res, next) {
  const authHeader = req.headers['authorization'];

  if (!authHeader) {
    return res.status(401).json({ error: 'Токен не предоставлен' });
  }

  // Ожидаем формат: "Bearer eyJhbGc..."
  const token = authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Неверный формат токена' });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.userId = decoded.userId;
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Недействительный токен' });
  }
}

module.exports = authMiddleware;