const controls='button,a,input,select,textarea,label,summary,[contenteditable]:not([contenteditable="false"]),[role="button"],[role="checkbox"],[role="link"],[role="combobox"],[role="switch"],[role="textbox"]';
export function isRowSurface(event){
 const control=event.target?.closest?.(controls);
 return !event.defaultPrevented&&(!control||control===event.currentTarget);
}
/** Call only with an existing read-only Details opener, never a business command. */
export function detailsRowHandlers(pointer,select,open,disabled=false){
 return {
  onPointerDown:event=>{pointer.current=event.pointerType;},
  onClick:event=>{if(!disabled&&isRowSurface(event))select();},
  onDoubleClick:event=>{if(!disabled&&pointer.current!=='touch'&&isRowSurface(event)){select();open();}},
  onKeyDown:event=>{if(!disabled&&isRowSurface(event)&&event.target===event.currentTarget&&['Enter',' '].includes(event.key)){
   event.preventDefault();select();if(event.key==='Enter')open();
  }},
 };
}
