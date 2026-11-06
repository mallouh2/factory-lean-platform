// Shared scalar transport, before JSON.parse can round PostgreSQL numeric.
// String tokens are indivisible; booleans/null and escaped labels stay intact.
export function exactJsonNumbers(text){
 if(typeof text!=='string'||new TextEncoder().encode(text).length>2*1024*1024)throw Error('exact_json_invalid');
 const result=text.replace(/"(?:\\.|[^"\\])*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/g,
  token=>token[0]==='"'?token:JSON.stringify(token));
 JSON.parse(result);return result;
}
