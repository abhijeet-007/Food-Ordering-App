// ── Cart state ────────────────────────────────────────────────────────────
const cart = [];

function addToCart(btn, name, price) {
  const existing = cart.find(i => i.name === name);
  if (existing) {
    existing.qty += 1;
  } else {
    cart.push({ name, price, qty: 1 });
  }

  btn.textContent = '✓ Added';
  btn.classList.add('added');
  setTimeout(() => {
    btn.textContent = '+ Add';
    btn.classList.remove('added');
  }, 1200);

  renderCart();
  showToast(`${name} added to cart`);
}

function renderCart() {
  const list  = document.getElementById('cartItems');
  const total = document.getElementById('cartTotal');
  const count = document.getElementById('cartCount');

  list.innerHTML = cart.map(i =>
    `<li><span>${i.name} ×${i.qty}</span><span>$${(i.price * i.qty).toFixed(2)}</span></li>`
  ).join('');

  const sum = cart.reduce((acc, i) => acc + i.price * i.qty, 0);
  total.textContent = `$${sum.toFixed(2)}`;
  count.textContent = cart.reduce((acc, i) => acc + i.qty, 0);
}

function toggleCart() {
  document.getElementById('cartPanel').classList.toggle('open');
}

function checkout() {
  if (cart.length === 0) { showToast('Your cart is empty!'); return; }
  cart.length = 0;
  renderCart();
  document.getElementById('cartPanel').classList.remove('open');
  showToast('🎉 Order placed! Delivering in ~28 min');
}

// ── Toast ─────────────────────────────────────────────────────────────────
function showToast(msg) {
  const toast = document.getElementById('toast');
  toast.textContent = msg;
  toast.classList.add('show');
  setTimeout(() => toast.classList.remove('show'), 2500);
}

// ── Category filter ───────────────────────────────────────────────────────
document.querySelectorAll('.cat').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.cat').forEach(b => b.classList.remove('cat--active'));
    btn.classList.add('cat--active');

    const filter = btn.dataset.filter;
    document.querySelectorAll('.card').forEach(card => {
      const cats = card.dataset.category || '';
      card.style.display = (filter === 'all' || cats.includes(filter)) ? '' : 'none';
    });
  });
});

// ── Mobile nav ────────────────────────────────────────────────────────────
document.querySelector('.nav__burger').addEventListener('click', () => {
  document.querySelector('.nav__links').classList.toggle('open');
});

// ── Order form ────────────────────────────────────────────────────────────
function handleOrder(e) {
  e.preventDefault();
  showToast('📍 Finding restaurants near you...');
  e.target.reset();
}

// ── Close cart on outside click ───────────────────────────────────────────
document.addEventListener('click', e => {
  const widget = document.getElementById('cartWidget');
  if (!widget.contains(e.target)) {
    document.getElementById('cartPanel').classList.remove('open');
  }
});
