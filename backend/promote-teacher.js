const Database=require('better-sqlite3');
const path=require('path');
const db=new Database(path.join(process.env.DATA_DIR||'./data','studyside.sqlite'));
const email=String(process.argv[2]||'').trim().toLowerCase();
if(!/^\S+@\S+\.\S+$/.test(email)){console.error('Usage: npm run promote-teacher -- teacher@example.com');process.exit(1);}
const result=db.prepare("UPDATE users SET role='teacher' WHERE email=?").run(email);
if(!result.changes){console.error('No account found for '+email+'. Ask the person to register first.');process.exit(1);}
console.log('Teacher role granted to '+email);
db.close();
