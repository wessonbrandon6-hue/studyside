const express=require('express');
const helmet=require('helmet');
const cors=require('cors');
const rateLimit=require('express-rate-limit');
const bcrypt=require('bcryptjs');
const jwt=require('jsonwebtoken');
const Database=require('better-sqlite3');
const multer=require('multer');
const fs=require('fs');
const path=require('path');
const crypto=require('crypto');

const app=express();
const PORT=Number(process.env.PORT||3000);
const DATA_DIR=path.resolve(process.env.DATA_DIR||'./data');
const UPLOAD_DIR=path.join(DATA_DIR,'uploads');
fs.mkdirSync(UPLOAD_DIR,{recursive:true});
if(!process.env.JWT_SECRET||process.env.JWT_SECRET.length<32) {
  console.error('JWT_SECRET must be set to a random secret of at least 32 characters.');
  process.exit(1);
}
const allowedOrigins=(process.env.ALLOWED_ORIGINS||'https://wessonbrandon6-hue.github.io').split(',').map(x=>x.trim()).filter(Boolean);
const db=new Database(path.join(DATA_DIR,'studyside.sqlite'));
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');
db.exec(`
CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,email TEXT NOT NULL UNIQUE,password_hash TEXT NOT NULL,display_name TEXT NOT NULL,role TEXT NOT NULL DEFAULT 'student' CHECK(role IN ('student','teacher','admin')),created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS classes(id TEXT PRIMARY KEY,name TEXT NOT NULL,description TEXT DEFAULT '',teacher_id TEXT NOT NULL REFERENCES users(id),join_code TEXT NOT NULL UNIQUE,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS memberships(class_id TEXT NOT NULL REFERENCES classes(id) ON DELETE CASCADE,student_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,joined_at TEXT NOT NULL,PRIMARY KEY(class_id,student_id));
CREATE TABLE IF NOT EXISTS resources(id TEXT PRIMARY KEY,owner_id TEXT NOT NULL REFERENCES users(id),class_id TEXT REFERENCES classes(id) ON DELETE CASCADE,title TEXT NOT NULL,description TEXT DEFAULT '',file_name TEXT NOT NULL,stored_name TEXT NOT NULL,mime_type TEXT NOT NULL,size INTEGER NOT NULL,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS quizzes(id TEXT PRIMARY KEY,author_id TEXT NOT NULL REFERENCES users(id),class_id TEXT REFERENCES classes(id) ON DELETE CASCADE,title TEXT NOT NULL,subject TEXT NOT NULL,description TEXT DEFAULT '',questions_json TEXT NOT NULL,published INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS attempts(id TEXT PRIMARY KEY,quiz_id TEXT NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,student_id TEXT NOT NULL REFERENCES users(id),answers_json TEXT NOT NULL,score INTEGER NOT NULL,correct_count INTEGER NOT NULL,total_questions INTEGER NOT NULL,submitted_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS announcements(id TEXT PRIMARY KEY,author_id TEXT NOT NULL REFERENCES users(id),class_id TEXT REFERENCES classes(id) ON DELETE CASCADE,title TEXT NOT NULL,body TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS idx_members_student ON memberships(student_id);
CREATE INDEX IF NOT EXISTS idx_resources_class ON resources(class_id);
CREATE INDEX IF NOT EXISTS idx_quizzes_class ON quizzes(class_id);
CREATE INDEX IF NOT EXISTS idx_attempts_quiz ON attempts(quiz_id);
`);

const now=()=>new Date().toISOString();
const id=()=>crypto.randomUUID();
const cleanEmail=s=>String(s||'').trim().toLowerCase();
const safeUser=u=>({id:u.id,email:u.email,displayName:u.display_name,role:u.role,createdAt:u.created_at});
const fail=(res,status,message)=>res.status(status).json({error:message});
app.disable('x-powered-by');
app.use(helmet({crossOriginResourcePolicy:{policy:'cross-origin'}}));
app.use(cors({origin(origin,cb){if(!origin||allowedOrigins.includes(origin))return cb(null,true);return cb(new Error('Origin not allowed'));},credentials:false}));
app.use(express.json({limit:'1mb'}));
app.use('/api/',rateLimit({windowMs:15*60*1000,limit:250,standardHeaders:true,legacyHeaders:false}));
app.get('/api/health',(req,res)=>res.json({ok:true,service:'StudySide API',version:'1.0.0',time:now()}));

function auth(req,res,next){
 const h=req.headers.authorization||'',token=h.startsWith('Bearer ')?h.slice(7):'';
 try{const p=jwt.verify(token,process.env.JWT_SECRET,{issuer:'studyside-api'});const u=db.prepare('SELECT * FROM users WHERE id=?').get(p.sub);if(!u)return fail(res,401,'Account not found');req.user=u;next();}
 catch{return fail(res,401,'Please sign in again.');}
}
const teacher=(req,res,next)=>['teacher','admin'].includes(req.user.role)?next():fail(res,403,'Teacher access required.');
const member=(classId,user)=>!!db.prepare('SELECT 1 FROM memberships WHERE class_id=? AND student_id=?').get(classId,user.id)||!!db.prepare('SELECT 1 FROM classes WHERE id=? AND teacher_id=?').get(classId,user.id);
const canSeeClass=(classId,user)=>!classId||member(classId,user);
const tokenFor=u=>jwt.sign({sub:u.id},process.env.JWT_SECRET,{expiresIn:'7d',issuer:'studyside-api'});
const upload=multer({storage:multer.diskStorage({destination:(req,file,cb)=>cb(null,UPLOAD_DIR),filename:(req,file,cb)=>cb(null,crypto.randomUUID()+path.extname(file.originalname).slice(0,12).toLowerCase())}),limits:{fileSize:20*1024*1024},fileFilter:(req,file,cb)=>{const ext=path.extname(file.originalname).toLowerCase();const allowed=['.pdf','.png','.jpg','.jpeg','.webp','.doc','.docx','.ppt','.pptx','.txt','.csv'];cb(allowed.includes(ext)?null:new Error('File type not allowed.'),allowed.includes(ext));}});

app.post('/api/auth/register',async(req,res)=>{
 try{
  const displayName=String(req.body.displayName||'').trim().slice(0,80),email=cleanEmail(req.body.email),password=String(req.body.password||'');
  if(displayName.length<2)return fail(res,400,'Enter a display name of at least 2 characters.');
  if(!/^\S+@\S+\.\S+$/.test(email))return fail(res,400,'Enter a valid email address.');
  if(password.length<10)return fail(res,400,'Use a password with at least 10 characters.');
  if(password.length>200)return fail(res,400,'Password is too long.');
  const role=(process.env.TEACHER_EMAILS||'').split(',').map(cleanEmail).includes(email)?'teacher':'student';
  const user={id:id(),email,password_hash:await bcrypt.hash(password,12),display_name:displayName,role,created_at:now()};
  db.prepare('INSERT INTO users VALUES(?,?,?,?,?,?)').run(user.id,user.email,user.password_hash,user.display_name,user.role,user.created_at);
  res.status(201).json({token:tokenFor(user),user:safeUser(user)});
 }catch(e){if(String(e.code).startsWith('SQLITE_CONSTRAINT'))return fail(res,409,'An account with that email already exists.');console.error(e);fail(res,500,'Could not create account.');}
});
app.post('/api/auth/login',async(req,res)=>{
 const email=cleanEmail(req.body.email),password=String(req.body.password||''),u=db.prepare('SELECT * FROM users WHERE email=?').get(email);
 if(!u||!(await bcrypt.compare(password,u.password_hash)))return fail(res,401,'Email or password is incorrect.');
 res.json({token:tokenFor(u),user:safeUser(u)});
});
app.get('/api/auth/me',auth,(req,res)=>res.json({user:safeUser(req.user)}));

app.get('/api/classes',auth,(req,res)=>{
 const rows=db.prepare(`SELECT c.*,u.display_name teacher_name,(SELECT COUNT(*) FROM memberships m WHERE m.class_id=c.id) student_count,
 CASE WHEN c.teacher_id=? THEN 1 ELSE 0 END is_teacher FROM classes c JOIN users u ON u.id=c.teacher_id
 WHERE c.teacher_id=? OR c.id IN(SELECT class_id FROM memberships WHERE student_id=?) ORDER BY c.created_at DESC`).all(req.user.id,req.user.id,req.user.id);
 res.json({classes:rows.map(c=>({...c,joinCode:c.is_teacher?c.join_code:undefined,join_code:undefined}))});
});
app.post('/api/classes',auth,teacher,(req,res)=>{
 const name=String(req.body.name||'').trim().slice(0,100),description=String(req.body.description||'').trim().slice(0,500);
 if(name.length<2)return fail(res,400,'Class name is required.');
 let code;do{code=crypto.randomBytes(4).toString('hex').toUpperCase();}while(db.prepare('SELECT 1 FROM classes WHERE join_code=?').get(code));
 const c={id:id(),name,description,teacher_id:req.user.id,join_code:code,created_at:now()};
 db.prepare('INSERT INTO classes VALUES(?,?,?,?,?,?)').run(c.id,c.name,c.description,c.teacher_id,c.join_code,c.created_at);
 res.status(201).json({class:{...c,joinCode:code}});
});
app.post('/api/classes/join',auth,(req,res)=>{
 const code=String(req.body.code||'').trim().toUpperCase(),c=db.prepare('SELECT * FROM classes WHERE join_code=?').get(code);
 if(!c)return fail(res,404,'That class code was not found.');
 if(c.teacher_id===req.user.id)return fail(res,400,'You already teach this class.');
 db.prepare('INSERT OR IGNORE INTO memberships VALUES(?,?,?)').run(c.id,req.user.id,now());
 res.json({ok:true,class:{id:c.id,name:c.name}});
});

app.get('/api/resources',auth,(req,res)=>{
 const rows=db.prepare(`SELECT r.*,u.display_name owner_name FROM resources r JOIN users u ON u.id=r.owner_id
 WHERE r.class_id IS NULL OR r.class_id IN(SELECT class_id FROM memberships WHERE student_id=?) OR r.class_id IN(SELECT id FROM classes WHERE teacher_id=?)
 ORDER BY r.created_at DESC`).all(req.user.id,req.user.id);
 res.json({resources:rows.map(r=>({...r,stored_name:undefined,downloadUrl:'/api/resources/'+r.id+'/download'}))});
});
app.post('/api/resources',auth,teacher,upload.single('file'),(req,res)=>{
 if(!req.file)return fail(res,400,'Choose a file to upload.');
 try{
  const classId=req.body.classId||null;
  if(classId&&!db.prepare('SELECT 1 FROM classes WHERE id=? AND teacher_id=?').get(classId,req.user.id)){fs.unlinkSync(req.file.path);return fail(res,403,'You can only share resources with your own classes.');}
  const r={id:id(),owner_id:req.user.id,class_id:classId,title:String(req.body.title||req.file.originalname).slice(0,140),description:String(req.body.description||'').slice(0,1000),file_name:path.basename(req.file.originalname).slice(0,200),stored_name:req.file.filename,mime_type:req.file.mimetype,size:req.file.size,created_at:now()};
  db.prepare('INSERT INTO resources VALUES(?,?,?,?,?,?,?,?,?,?)').run(r.id,r.owner_id,r.class_id,r.title,r.description,r.file_name,r.stored_name,r.mime_type,r.size,r.created_at);
  res.status(201).json({resource:{...r,stored_name:undefined}});
 }catch(e){fs.unlinkSync(req.file.path);console.error(e);fail(res,500,'Could not save resource.');}
});
app.get('/api/resources/:id/download',auth,(req,res)=>{
 const r=db.prepare('SELECT * FROM resources WHERE id=?').get(req.params.id);
 if(!r||!canSeeClass(r.class_id,req.user))return fail(res,404,'Resource not found.');
 const file=path.join(UPLOAD_DIR,r.stored_name);if(!fs.existsSync(file))return fail(res,404,'File is missing from storage.');
 res.download(file,r.file_name);
});

function parseQuestions(raw){
 if(!Array.isArray(raw)||raw.length<1||raw.length>100)throw new Error('A quiz must contain 1 to 100 questions.');
 return raw.map((q,i)=>{
  if(!q||typeof q.q!=='string'||!q.q.trim()||!Array.isArray(q.options)||q.options.length<2||q.options.length>6||!Number.isInteger(q.answer)||q.answer<0||q.answer>=q.options.length)throw new Error('Question '+(i+1)+' needs text, 2–6 options and a valid answer index.');
  return {q:q.q.trim().slice(0,1000),options:q.options.map(x=>String(x).slice(0,500)),answer:q.answer,explanation:String(q.explanation||'').slice(0,1000)};
 });
}
app.get('/api/quizzes',auth,(req,res)=>{
 const rows=db.prepare(`SELECT * FROM quizzes WHERE published=1 AND (class_id IS NULL OR class_id IN(SELECT class_id FROM memberships WHERE student_id=?) OR class_id IN(SELECT id FROM classes WHERE teacher_id=?)) ORDER BY created_at DESC`).all(req.user.id,req.user.id);
 res.json({quizzes:rows.map(q=>({id:q.id,title:q.title,subject:q.subject,description:q.description,classId:q.class_id,createdAt:q.created_at,questions:JSON.parse(q.questions_json).map(({answer, ...safe})=>safe)}))});
});
app.post('/api/quizzes',auth,teacher,(req,res)=>{
 try{
  const title=String(req.body.title||'').trim().slice(0,140),subject=String(req.body.subject||'General').slice(0,80),classId=req.body.classId||null;
  if(title.length<2)return fail(res,400,'Quiz title is required.');
  if(classId&&!db.prepare('SELECT 1 FROM classes WHERE id=? AND teacher_id=?').get(classId,req.user.id))return fail(res,403,'Choose one of your own classes.');
  const questions=parseQuestions(req.body.questions),q={id:id(),author_id:req.user.id,class_id:classId,title,subject,description:String(req.body.description||'').slice(0,1000),questions_json:JSON.stringify(questions),published:1,created_at:now()};
  db.prepare('INSERT INTO quizzes VALUES(?,?,?,?,?,?,?,?,?)').run(q.id,q.author_id,q.class_id,q.title,q.subject,q.description,q.questions_json,q.published,q.created_at);
  res.status(201).json({quiz:{id:q.id,title:q.title,subject:q.subject,questionCount:questions.length}});
 }catch(e){fail(res,400,e.message);}
});
app.post('/api/quizzes/:id/attempts',auth,(req,res)=>{
 const q=db.prepare('SELECT * FROM quizzes WHERE id=? AND published=1').get(req.params.id);
 if(!q||!canSeeClass(q.class_id,req.user))return fail(res,404,'Quiz not found.');
 const questions=JSON.parse(q.questions_json),answers=req.body.answers;
 if(!Array.isArray(answers)||answers.length!==questions.length||answers.some(x=>!Number.isInteger(x)||x<0||x>5))return fail(res,400,'Submit one valid choice for every question.');
 let correct=0;questions.forEach((q,i)=>{if(answers[i]===q.answer)correct++;});
 const score=Math.round(correct/questions.length*100),a={id:id(),quiz_id:q.id,student_id:req.user.id,answers_json:JSON.stringify(answers),score,correct_count:correct,total_questions:questions.length,submitted_at:now()};
 db.prepare('INSERT INTO attempts VALUES(?,?,?,?,?,?,?,?)').run(a.id,a.quiz_id,a.student_id,a.answers_json,a.score,a.correct_count,a.total_questions,a.submitted_at);
 res.status(201).json({score,correct,total:questions.length,submittedAt:a.submitted_at,feedback:questions.map((q,i)=>({correct:answers[i]===q.answer,explanation:q.explanation}))});
});
app.get('/api/teacher/dashboard',auth,teacher,(req,res)=>{
 const classes=db.prepare('SELECT * FROM classes WHERE teacher_id=? ORDER BY created_at DESC').all(req.user.id);
 const classIds=classes.map(c=>c.id);const placeholders=classIds.map(()=>'?').join(',');
 const students=classIds.length?db.prepare('SELECT COUNT(*) n FROM memberships WHERE class_id IN('+placeholders+')').get(...classIds).n:0;
 const quizzes=classIds.length?db.prepare('SELECT id,title,class_id FROM quizzes WHERE author_id=? OR class_id IN('+placeholders+')').all(req.user.id,...classIds):db.prepare('SELECT id,title,class_id FROM quizzes WHERE author_id=?').all(req.user.id);
 const attempts=quizzes.length?db.prepare(`SELECT a.score,a.submitted_at,u.display_name student_name,q.title quiz_title FROM attempts a JOIN users u ON u.id=a.student_id JOIN quizzes q ON q.id=a.quiz_id WHERE a.quiz_id IN(${quizzes.map(()=>'?').join(',')}) ORDER BY a.submitted_at DESC LIMIT 50`).all(...quizzes.map(q=>q.id)):[];
 res.json({classCount:classes.length,studentEnrolments:students,quizCount:quizzes.length,attempts});
});
app.get('/api/announcements',auth,(req,res)=>{
 const rows=db.prepare(`SELECT a.*,u.display_name author_name FROM announcements a JOIN users u ON u.id=a.author_id WHERE a.class_id IS NULL OR a.class_id IN(SELECT class_id FROM memberships WHERE student_id=?) OR a.class_id IN(SELECT id FROM classes WHERE teacher_id=?) ORDER BY a.created_at DESC LIMIT 100`).all(req.user.id,req.user.id);
 res.json({announcements:rows});
});
app.post('/api/announcements',auth,teacher,(req,res)=>{
 const title=String(req.body.title||'').trim().slice(0,140),body=String(req.body.body||'').trim().slice(0,3000),classId=req.body.classId||null;
 if(!title||!body)return fail(res,400,'Announcement title and message are required.');
 if(classId&&!db.prepare('SELECT 1 FROM classes WHERE id=? AND teacher_id=?').get(classId,req.user.id))return fail(res,403,'You can only post to your own classes.');
 const a={id:id(),author_id:req.user.id,class_id:classId,title,body,created_at:now()};
 db.prepare('INSERT INTO announcements VALUES(?,?,?,?,?,?)').run(a.id,a.author_id,a.class_id,a.title,a.body,a.created_at);
 res.status(201).json({announcement:a});
});

app.use((err,req,res,next)=>{if(err instanceof multer.MulterError)return fail(res,400,err.code==='LIMIT_FILE_SIZE'?'Maximum file size is 20 MB.':err.message);if(err.message==='Origin not allowed')return fail(res,403,err.message);console.error(err);fail(res,400,err.message||'Request failed.');});
app.listen(PORT,'0.0.0.0',()=>console.log('StudySide API listening on '+PORT));
