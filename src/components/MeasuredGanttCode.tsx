import {useEffect,useRef,useState} from 'react';
/** Measure actual text against the bar interior; geometry always remains time based. */
export default function MeasuredGanttCode({code}:{code:string}){
 const box=useRef<HTMLSpanElement>(null),text=useRef<HTMLElement>(null),[fits,setFits]=useState(false);
 useEffect(()=>{const b=box.current,p=text.current;if(!b||!p)return;const measure=()=>setFits(p.getBoundingClientRect().width<=b.clientWidth&&b.clientWidth>0);measure();const observer=new ResizeObserver(measure);observer.observe(b);observer.observe(p);return()=>observer.disconnect();},[code]);
 return <span ref={box} className="planning-inline-code" aria-hidden="true" data-fits={fits}><bdi ref={text} dir="ltr">{code}</bdi></span>;
}
