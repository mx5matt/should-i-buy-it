(() => {
  'use strict';
  const root = document.querySelector('[data-dashboard-results]');
  if (!root) return;
  const rows = [...root.querySelectorAll('[data-dashboard-item]')];
  const original = rows.map((el, index) => ({el, index, parent:el.parentElement, text:(el.textContent || '').toLocaleLowerCase()}));
  const groups = [...root.querySelectorAll('[data-dashboard-group]')];
  const tools = document.createElement('form');
  tools.className = 'dashboard-tools'; tools.setAttribute('role','search'); tools.method = 'get';
  const searchLabel = document.createElement('label'); searchLabel.textContent = 'Search results';
  const search = document.createElement('input'); search.type='search'; search.name='q'; search.placeholder='Search names and details';
  search.value = new URL(location.href).searchParams.get('q') || '';
  searchLabel.append(search);
  const sortLabel = document.createElement('label'); sortLabel.textContent='Sort results';
  const sort = document.createElement('select'); sort.name='sort';
  [['default','Original order'],['name','Name A to Z'],['name_desc','Name Z to A']].forEach(([v,t])=>sort.add(new Option(t,v)));
  sort.value = new URL(location.href).searchParams.get('sort') || 'default';
  sortLabel.append(sort);
  const clear = document.createElement('a'); clear.textContent='Clear search and sort';
  const resetURL = new URL(location.href); resetURL.searchParams.delete('q'); resetURL.searchParams.delete('sort');
  clear.href=resetURL.pathname+resetURL.search+resetURL.hash;
  tools.append(searchLabel,sortLabel,clear);
  const count = document.createElement('p'); count.className='dashboard-count'; count.setAttribute('role','status'); count.setAttribute('aria-live','polite');
  const empty = document.createElement('p'); empty.className='dashboard-empty'; empty.textContent='No matching results. Try another search or clear your search.';
  root.before(tools,count); root.after(empty);
  const storageKey=()=> 'dashboard-scroll:'+location.pathname+location.search;
  const savePosition=()=>{try{sessionStorage.setItem(storageKey(),JSON.stringify({y:scrollY,time:Date.now()}));}catch(_){}};
  let dirty=false;
  const initialValues=new WeakMap();
  document.querySelectorAll('form:not(.dashboard-tools) input, form:not(.dashboard-tools) textarea, form:not(.dashboard-tools) select').forEach(el=>{
    initialValues.set(el,el.type==='checkbox'||el.type==='radio'?el.checked:el.value);
  });
  document.addEventListener('input',event=>{
    const el=event.target;
    if(!el.closest('form')||el.closest('.dashboard-tools')||!initialValues.has(el))return;
    dirty= [...document.querySelectorAll('form:not(.dashboard-tools) input, form:not(.dashboard-tools) textarea, form:not(.dashboard-tools) select')].some(input=>initialValues.has(input) && initialValues.get(input)!==(input.type==='checkbox'||input.type==='radio'?input.checked:input.value));
  });
  document.addEventListener('change',event=>{if(event.target.matches('input,select,textarea'))event.target.dispatchEvent(new Event('input',{bubbles:true}));});
  document.addEventListener('submit',event=>{
    if(event.target!==tools){dirty=false;savePosition();}
  });
  window.addEventListener('beforeunload',event=>{
    if(dirty){event.preventDefault();event.returnValue='';}
  });
  function syncReturnTargets(){
    document.querySelectorAll('form').forEach(form=>{
      if((form.method||'').toLowerCase()!=='post')return;
      let input=form.querySelector('input[name="return_to"]');
      if(!input){input=document.createElement('input');input.type='hidden';input.name='return_to';form.append(input);}
      input.value=location.pathname+location.search;
    });
  }
  function update(){
    const q=search.value.trim().toLocaleLowerCase(); const order=sort.value;
    const sorted=[...original].sort((a,b)=>order==='name'?a.text.localeCompare(b.text):order==='name_desc'?b.text.localeCompare(a.text):a.index-b.index);
    let visible=0;
    sorted.forEach(item=>{
      item.el.hidden=!item.text.includes(q); if(!item.el.hidden)visible++;
      // Preserve each element's original parent (especially tbody in tables).
      item.parent.appendChild(item.el);
    });
    groups.forEach(group=>{group.hidden=!group.querySelector('[data-dashboard-item]:not([hidden])');});
    count.textContent=`Showing ${visible} of ${original.length}`; empty.hidden=visible!==0;
    const url=new URL(location.href);
    q?url.searchParams.set('q',search.value.trim()):url.searchParams.delete('q');
    order!=='default'?url.searchParams.set('sort',order):url.searchParams.delete('sort');
    history.replaceState(history.state,'',url.pathname+url.search+url.hash);
    syncReturnTargets();
  }
  tools.addEventListener('submit',event=>event.preventDefault());
  search.addEventListener('input',update); sort.addEventListener('change',update);
  update();
  const navigation=performance.getEntriesByType('navigation')[0];
  const refreshRequested=(history.state||{}).dashboardRestore===true;
  const nativeReload=navigation && navigation.type==='reload';
  if(refreshRequested||nativeReload){
    try{
      const stored=JSON.parse(sessionStorage.getItem(storageKey())||'null');
      if(stored&&Number.isFinite(stored.y)&&Date.now()-stored.time<120000){
        history.scrollRestoration='manual';
        const restore=()=>scrollTo(0,stored.y);
        requestAnimationFrame(()=>requestAnimationFrame(restore));
        setTimeout(restore,150);setTimeout(restore,500);
      }
      sessionStorage.removeItem(storageKey());
    }catch(_){}
    history.replaceState({...history.state,dashboardRestore:false},'');
  }
  window.addEventListener('pagehide',()=>{if(!dirty)savePosition();});
  window.dashboardRefresh=()=>{
    if(dirty){return false;}
    savePosition();history.replaceState({...history.state,dashboardRestore:true},'');
    location.reload();return true;
  };
})();
