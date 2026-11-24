import {useId,useState} from 'react';

// One searchable selector; typing clears the old identity until a valid option is chosen.
export default function EntityCombobox({label,options,value,onChange,onSearch,disabled=false,placeholder}:{label:string;options:{id:string;label:string}[];value:string;onChange:(id:string)=>void;onSearch?:(query:string)=>void;disabled?:boolean;placeholder:string}){
 const id=useId(),[open,setOpen]=useState(false),[query,setQuery]=useState<string|null>(null),[active,setActive]=useState(0);
 const selected=options.find(o=>o.id===value),matches=(onSearch?options:options.filter(o=>o.label.toLocaleLowerCase().includes((query||'').toLocaleLowerCase()))).slice(0,40);
 const choose=(option:{id:string;label:string})=>{onChange(option.id);onSearch?.('');setQuery(null);setOpen(false);setActive(0);};
 return <div className="entity-combobox" onBlur={e=>{if(!e.currentTarget.contains(e.relatedTarget)){setOpen(false);setQuery(null);onSearch?.('');}}}>
  <label htmlFor={id}>{label}</label><input id={id} role="combobox" autoComplete="off" aria-autocomplete="list" aria-expanded={open} aria-controls={id+'-options'} aria-activedescendant={open&&matches[active]?id+'-'+active:undefined} disabled={disabled} placeholder={placeholder} value={query??selected?.label??''}
   onFocus={()=>setOpen(true)} onChange={e=>{setQuery(e.target.value);onChange('');onSearch?.(e.target.value);setOpen(true);setActive(0);}}
   onKeyDown={e=>{if(e.key==='Escape'){setOpen(false);setQuery(null);onSearch?.('');e.stopPropagation();}else if(['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();setOpen(true);setActive(i=>Math.max(0,Math.min(matches.length-1,i+(e.key==='ArrowDown'?1:-1))));}else if(e.key==='Enter'&&open){e.preventDefault();if(matches[active])choose(matches[active]);}}}/>
  {open&&<ul id={id+'-options'} role="listbox">{matches.map((o,i)=><li id={id+'-'+i} key={o.id} role="option" aria-selected={i===active} onMouseDown={e=>e.preventDefault()} onClick={()=>choose(o)}>{o.label}</li>)}</ul>}
 </div>;
}
