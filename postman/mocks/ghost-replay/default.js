// Synthetic immutable replay, derived from GhostPlayback/OwnGhostReplay contracts.
// No production accounts, auth headers, record IDs or coordinates are retained.
const http = require('http');
http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const match = url.pathname.match(/^\/api\/v1\/runs\/records\/([^/]+)\/(ghost-playback|public-ghost-playback)$/);
  if (!match || req.method !== 'GET') {
    res.writeHead(501, {'content-type': 'application/json'});
    return res.end(JSON.stringify({code:'UNMODELED',data:null}));
  }
  if (match[1] === 'deleted') {
    res.writeHead(404, {'content-type': 'application/json'});
    return res.end(JSON.stringify({code:'RUN-002',message:'missing',data:null}));
  }
  const count = Number(match[1].split('-').pop()) || 3600;
  const playback = {
    sourceRecordId:match[1], version:'GHOST_PLAYBACK_V1', sourcePolicyVersion:'2026-10-14',
    course:{sessionId:'synthetic',courseId:'course',name:'Synthetic',version:3,
      route:[{lat:36,lng:127},{lat:36.01,lng:127}],totalDistanceMeters:1000},
    courseElapsedSeconds:count,durationMs:count*1000,eligible:true,unavailableReasons:[],
    samples:Array.from({length:count+1},(_,i)=>({elapsedMs:i*1000,coursePositionM:i*1000/count})),
    spans:Array.from({length:count},(_,i)=>({fromMs:i*1000,toMs:(i+1)*1000,
      fromPositionM:i*1000/count,toPositionM:(i+1)*1000/count,state:'TRACKED'})),
  };
  const data=match[2]==='ghost-playback'?playback:{publicPeriod:'ALL',
    candidate:{runRecordId:match[1],memberId:'other',rank:1,courseElapsedSeconds:count},playback};
  const body=JSON.stringify({result:'SUCCESS',data});
  res.writeHead(200, {'content-type':'application/json','content-length':Buffer.byteLength(body)});
  // Real stream transport instead of replacing the caller's HTTP adapter.
  const half=Math.floor(body.length/2);
  res.write(body.slice(0,half));
  setTimeout(()=>res.end(body.slice(half)),20);
}).listen(process.env.PORT);
