import {useEffect, useState} from 'react';
import SidebarIcon from './NavigationIcon';
import {navigationLabel, operationalNavigation} from '@/utils/operational-navigation.mjs';

type Props = {
  can:(module:string,action?:string)=>boolean;
  t:(key:string)=>string;
  active:string;
  expanded:boolean;
  onExpand:()=>void;
  onNavigate:(destination:string)=>void;
};

export default function OperationalNavigation({can,t,active,expanded,onExpand,onNavigate}:Props) {
  const groups=operationalNavigation(can);
  const activeGroup=groups.find(group=>group.items.length>1&&group.items.includes(active)&&group.primary!==active)?.id;
  const [open,setOpen]=useState<string[]>(activeGroup?[activeGroup]:[]);
  useEffect(()=>{if(activeGroup)setOpen(previous=>previous.includes(activeGroup)?previous:[...previous,activeGroup]);},[activeGroup]);
  function destination(item:string,label=navigationLabel(item),icon=item) {
    return <button key={item} type="button" title={t(label)} aria-label={t(label)} data-destination={item}
      aria-current={active===item||(item==='lean'&&active==='downtime')?'page':undefined}
      onClick={()=>onNavigate(item)}>
      <SidebarIcon name={icon}/><span className="nav-label">{t(label)}</span>
    </button>;
  }
  return <nav className="operational-navigation" aria-label={t('operations')}>
    {groups.map(group=>{
      if(group.items.length===1) {
        const item=group.items[0];
        return <div className="nav-direct" key={group.id}>{destination(item,group.id==='lean'?'lean':navigationLabel(item),group.id==='administration'?item:group.id==='production'?(item==='manageLinesMachines'?item:'floor'):group.id==='lean'?'lean':item)}</div>;
      }
      const isOpen=open.includes(group.id),children=group.items.filter(item=>item!==group.primary),id=`navigation-${group.id}`;
      const icon=group.id==='administration'?'settings':group.id;
      const preferred=group.id==='production'?'floor':group.id==='warehouse'?'warehouse':null;
      const parent=preferred&&group.items.includes(preferred)?preferred:null;
      const toggle=()=>{
        if(!expanded){onExpand();setOpen(previous=>previous.includes(group.id)?previous:[...previous,group.id]);return;}
        setOpen(previous=>previous.includes(group.id)?previous.filter(value=>value!==group.id):[...previous,group.id]);
      };
      const chevron=<span className="nav-chevron" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="m9 5 7 7-7 7"/></svg></span>;
      return <section className="nav-group" data-group={group.id} data-open={isOpen} data-active={group.items.includes(active)} key={group.id}>
        <div className={group.primary||parent?'nav-group-heading nav-split':'nav-group-heading'}>
          {group.primary?destination(group.primary,group.label,icon):parent?<button type="button" title={t(group.label)} aria-label={t(group.label)} onClick={()=>{onNavigate(parent);onExpand();setOpen(previous=>previous.includes(group.id)?previous:[...previous,group.id]);}}><SidebarIcon name={icon}/><span className="nav-label">{t(group.label)}</span></button>:null}
          <button className="nav-group-toggle" type="button" title={t(group.label)}
            aria-label={group.primary||parent?`${t('navMore')} · ${t(group.label)}`:t(group.label)} aria-expanded={isOpen&&expanded} aria-controls={id} onClick={event=>{event.stopPropagation();toggle();}}>
            {!group.primary&&!parent&&<><SidebarIcon name={icon}/><span className="nav-label">{t(group.label)}</span></>}{chevron}
          </button>
        </div>
        <div className="nav-submenu" id={id} inert={!isOpen||!expanded} aria-hidden={!isOpen||!expanded}>
          <div className="nav-submenu-clip"><div className="nav-submenu-items">{children.map(item=>destination(item))}</div></div>
        </div>
      </section>;
    })}
  </nav>;
}
