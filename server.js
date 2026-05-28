require('dotenv').config();

const express = require('express');
const app = express();
app.use(express.json());

const handler = require('./api/generate');
app.post('/api/generate',(req, res) => handler(req, res));

app.listen(3000, () => {
  console.log('Server running on port 3000');
} );

