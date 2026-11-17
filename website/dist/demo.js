(() => {
  "use strict";

  const cursors = window.PLAYPOINTER_CURSORS;
  const arena = document.querySelector("#arena");
  const demo = document.querySelector("#demo") || arena;
  const pointer = document.querySelector("#arena-cursor");
  const pointerImage = pointer?.querySelector("img");
  const pointerRod = pointer?.querySelector(".arena-cursor__rod");
  const cursorSize = document.querySelector("#cursor-size");
  const cursorSizeValue = document.querySelector("#cursor-size-value");
  const clickStrength = document.querySelector("#click-strength");
  const effects = document.querySelector("#arena-effects");
  const activeName = document.querySelector("#active-cursor");
  const grid = document.querySelector("#cursor-grid");
  const search = document.querySelector("#cursor-search");
  const count = document.querySelector("#catalog-count");
  const filterButtons = [...document.querySelectorAll("[data-filter]")];
  const demoButtons = [...document.querySelectorAll("[data-demo-cursor]")];
  const soundButtons = [...document.querySelectorAll("[data-sound]")];

  if (!cursors?.length || !arena || !pointerImage || !effects || !activeName || !grid || !search || !count) return;

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const categoryTerms = {
    cats: "коты кот котик котики кошка кошки кошачьи cats",
    fun: "приколы смешные весёлые необычные fun",
    classic: "классика обычные стрелка classic",
    laser: "лазер лазеры луч laser",
  };
  const effectTerms = {
    bongo: "бонго барабан лапки котик",
    rainbow: "радуга",
    laser: "лазер луч",
    spark: "искры",
    glow: "свечение",
    pounce: "прыжок лапа",
    comic: "комикс рука тык",
  };
  const rainbow = ["#ff638b", "#ffc55e", "#f8f17c", "#91f1ad", "#71d9ff", "#bc9cff"];
  const nyanFacingX = { right: -105, left: 5 };
  const nyanTail = { x: 0.25, y: 0.57 };
  const nyanTurnThreshold = 4;
  const strengthLevels = [0.35, 0.65, 1, 1.3, 1.65];
  const plural = new Intl.PluralRules("ru");
  const wavePlayers = new Map();
  let activeCursor;
  let selectedFilter = "all";
  let pressTimer;
  let nextBongoPaw = 0;
  let lastTrail = null;
  let trailColor = 0;
  let nyanTurnX = null;
  let pointerPosition = null;
  let activeRod;
  let gripX = null;
  let rodFrame = 0;
  let soundEnabled = false;
  let touchWave;
  let lastPressTime = -Infinity;
  let clickSeries = 0;
  let comicTap = null;

  effects.setAttribute("aria-hidden", "true");
  pointer.setAttribute("aria-hidden", "true");
  arena.setAttribute("aria-keyshortcuts", "Enter Space");
  if (!arena.hasAttribute("role")) arena.setAttribute("role", "button");
  if (!arena.hasAttribute("aria-label") && !arena.hasAttribute("aria-labelledby")) {
    arena.setAttribute("aria-label", "Попробовать курсор");
  }
  activeName.setAttribute("aria-live", "polite");
  activeName.setAttribute("aria-atomic", "true");
  count.setAttribute("role", "status");
  count.setAttribute("aria-atomic", "true");

  function normalize(value) {
    return value.toLocaleLowerCase("ru").replace(/ё/g, "е").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  }

  const cards = cursors.map((cursor) => {
    const button = document.createElement("button");
    const art = document.createElement("span");
    const image = document.createElement("img");
    const name = document.createElement("span");
    button.type = "button";
    button.className = "cursor-card";
    button.dataset.cursor = cursor.id;
    button.dataset.category = cursor.category;
    button.setAttribute("aria-pressed", "false");
    art.className = "cursor-card__art";
    image.alt = "";
    image.loading = "lazy";
    image.decoding = "async";
    image.src = cursor.image;
    name.className = "cursor-card__name";
    name.textContent = cursor.name;
    art.append(image);
    button.append(art, name);
    button.addEventListener("click", () => {
      selectCursor(cursor);
      arena.focus({ preventScroll: true });
      demo.scrollIntoView({ block: "start", behavior: reducedMotion.matches ? "auto" : "smooth" });
    });

    return {
      button,
      cursor,
      searchText: normalize([
        cursor.name, cursor.id, categoryTerms[cursor.category], effectTerms[cursor.effect], cursor.keywords,
      ].flat().filter(Boolean).join(" ")),
    };
  });

  function renderCatalog() {
    const terms = normalize(search.value).split(" ").filter(Boolean);
    const visibleCards = cards.filter(({ cursor, searchText }) => (
      (selectedFilter === "all" || cursor.category === selectedFilter) &&
      terms.every((term) => searchText.includes(term))
    ));
    grid.replaceChildren(...visibleCards.map(({ button }) => button));
    filterButtons.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.filter === selectedFilter));
    });

    const total = visibleCards.length;
    const noun = { one: "курсор", few: "курсора", many: "курсоров", other: "курсоров" }[plural.select(total)];
    count.textContent = total ? `${total} ${noun}` : "Курсоры не найдены";
  }

  function selectCursor(cursor) {
    if (activeCursor === cursor) return;
    activeCursor = cursor;
    nextBongoPaw = 0;
    touchWave = null;
    resetClickSeries();
    resetComicTap();
    clearTimeout(pressTimer);
    clearEffects();
    arena.classList.remove("is-pressed");
    arena.dataset.cursor = cursor.id;
    arena.dataset.effect = cursor.effect || "";
    arena.style.setProperty("--cursor-color", cursor.color || "#ffc36e");
    const [hotspotX, hotspotY] = cursor.hotspot || [0.5, 0.5];
    if (cursor.id === "funny21") {
      setNyanFacing("right");
    } else {
      delete arena.dataset.nyanFacing;
      pointer.style.setProperty("--hotspot-x", `${-hotspotX * 100}%`);
    }
    pointer.style.setProperty("--hotspot-y", `${-hotspotY * 100}%`);
    pointerImage.src = cursor.image;
    pointer.hidden = false;
    gripX = null;
    setRod(cursor.rod);
    centerPointer();
    activeName.textContent = cursor.name;
    cards.forEach(({ button, cursor: cardCursor }) => {
      button.setAttribute("aria-pressed", String(cardCursor === cursor));
    });
    demoButtons.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.demoCursor === cursor.id));
    });

    for (const frame of [cursor.pressed, cursor.alternate, cursor.pressedRod?.image]) {
      if (frame) new Image().src = frame;
    }
  }

  function setNyanFacing(facing) {
    arena.dataset.nyanFacing = facing;
    pointer.style.setProperty("--hotspot-x", `${nyanFacingX[facing]}%`);
  }

  function updateNyanFacing(x) {
    const facing = arena.dataset.nyanFacing;
    if (!facing) return;
    if (nyanTurnX === null || reducedMotion.matches) {
      nyanTurnX = x;
      return;
    }

    const movement = x - nyanTurnX;
    if (Math.abs(movement) < nyanTurnThreshold) return;
    nyanTurnX = x;
    const nextFacing = movement > 0 ? "right" : "left";
    if (nextFacing !== facing) setNyanFacing(nextFacing);
  }

  function centerPointer() {
    nyanTurnX = null;
    pointerPosition = null;
    pointer.style.left = "50%";
    pointer.style.top = "50%";
    requestRodPose();
    return { x: arena.clientWidth / 2, y: arena.clientHeight / 2 };
  }

  function placePointer(event) {
    const bounds = arena.getBoundingClientRect();
    const x = Math.max(0, Math.min(arena.clientWidth, event.clientX - bounds.left - arena.clientLeft));
    const y = Math.max(0, Math.min(arena.clientHeight, event.clientY - bounds.top - arena.clientTop));
    pointer.style.left = `${x}px`;
    pointer.style.top = `${y}px`;
    updateNyanFacing(x);
    if (event.pointerType !== "touch") arena.classList.add("is-pointer-active");
    pointerPosition = { x, y };
    requestRodPose();
    return pointerPosition;
  }

  function setRod(rod) {
    if (!pointerRod || activeRod === rod) return;
    activeRod = rod;
    pointerRod.hidden = !rod;
    if (!rod) {
      pointer.style.removeProperty("--rod-angle");
      return;
    }
    pointerRod.style.left = `${(rod.x - rod.width / 2) * 100}%`;
    pointerRod.style.top = `calc(${rod.y * 100}% - 1px)`;
    pointerRod.style.width = `${rod.width * 100}%`;
    pointerRod.style.backgroundImage = rod.image ? `url("${rod.image}")` : "";
    requestRodPose();
  }

  function requestRodPose() {
    if (activeRod && !rodFrame) rodFrame = requestAnimationFrame(renderRodPose);
  }

  function resetComicTap() {
    comicTap = null;
    pointer.style.removeProperty("--tap-scale-x");
    pointer.style.removeProperty("--tap-scale-y");
  }

  function renderRodPose() {
    rodFrame = 0;
    if (!activeRod) return;

    const arenaWidth = arena.clientWidth;
    const arenaHeight = arena.clientHeight;
    const point = pointerPosition || { x: arenaWidth / 2, y: arenaHeight / 2 };
    const gripLean = activeCursor.id === "comicHand" ? arenaHeight * 0.22 : arenaWidth * 0.30;
    const targetGripX = Math.min(arenaWidth * 1.05, Math.max(arenaWidth * 0.15, point.x + gripLean));
    const stillFollowing = gripX !== null && !reducedMotion.matches && Math.abs(targetGripX - gripX) > 0.5;
    gripX = stillFollowing ? gripX + (targetGripX - gripX) * 0.08 : targetGripX;

    const spriteSize = pointer.offsetWidth;
    let scaleX = 1;
    let scaleY = 1;
    if (comicTap) {
      const progress = Math.min(1, (performance.now() - comicTap.startedAt) / 240);
      const impulse = Math.sin(2 * Math.PI * progress) * Math.exp(-3 * progress) * comicTap.strength;
      scaleX += 0.12 * impulse;
      scaleY -= 0.16 * impulse;
      pointer.style.setProperty("--tap-scale-x", String(scaleX));
      pointer.style.setProperty("--tap-scale-y", String(scaleY));
      if (progress === 1) resetComicTap();
    }
    const [hotspotX, hotspotY] = activeCursor.hotspot || [0.5, 0.5];
    const jointX = (activeRod.x - hotspotX) * spriteSize * scaleX;
    const jointY = (activeRod.y - hotspotY) * spriteSize;
    const aimX = gripX - point.x;
    const aimY = arenaHeight * 1.12 - point.y;
    // Solve for the shaft length and angle without shifting the cursor's tip.
    const reach = Math.hypot(aimX, aimY);
    const shaftLength = Math.max(arenaHeight * 0.05, Math.sqrt(Math.max(0, reach * reach - jointX * jointX)) / scaleY - jointY);
    const angle = Math.atan2(aimY, aimX) - Math.atan2((jointY + shaftLength) * scaleY, jointX);
    pointer.style.setProperty("--rod-angle", `${angle}rad`);
    pointerRod.style.height = `${shaftLength + 1}px`;

    if (stillFollowing || comicTap) requestRodPose();
  }

  function clearEffects() {
    lastTrail = null;
    effects.replaceChildren();
  }

  function addEffect(type, { x, y }, {
    dx = 0, dy = 0, color = activeCursor.color || "#ffc36e", angle = 0, length = 0, size = 7, duration = 420,
  } = {}) {
    const particle = document.createElement("span");
    particle.className = `fx fx--${type}`;
    if (type === "bongo") particle.textContent = "♪";
    particle.style.left = `${x}px`;
    particle.style.top = `${y}px`;
    particle.style.setProperty("--fx-x", `${dx}px`);
    particle.style.setProperty("--fx-y", `${dy}px`);
    particle.style.setProperty("--fx-color", color);
    particle.style.setProperty("--fx-angle", `${angle}deg`);
    particle.style.setProperty("--fx-length", `${length}px`);
    particle.style.setProperty("--fx-size", `${size}px`);
    particle.style.setProperty("--fx-duration", `${duration}ms`);
    effects.append(particle);
    window.setTimeout(() => particle.remove(), duration);
  }

  function rainbowOrigin(point) {
    const facing = arena.dataset.nyanFacing;
    if (!facing) return point;
    const tailX = facing === "right" ? nyanTail.x : 1 - nyanTail.x;
    return {
      x: point.x + (nyanFacingX[facing] / 100 + tailX) * pointer.offsetWidth,
      y: point.y + (nyanTail.y - activeCursor.hotspot[1]) * pointer.offsetHeight,
    };
  }

  function addTrail(point, time) {
    if (activeCursor.effect !== "rainbow" || reducedMotion.matches) return;
    if (lastTrail && (time - lastTrail.time < 30 || Math.hypot(point.x - lastTrail.x, point.y - lastTrail.y) < 9)) return;
    lastTrail = { ...point, time };
    addEffect("rainbow", rainbowOrigin(point), { color: rainbow[trailColor], dy: 12, size: 9, duration: 480 });
    trailColor = (trailColor + 1) % rainbow.length;
  }

  function resetClickSeries() {
    lastPressTime = -Infinity;
    clickSeries = 0;
  }

  function pressStrength() {
    const now = performance.now();
    clickSeries = now - lastPressTime <= 400 ? Math.min(clickSeries + 1, 4) : 0;
    lastPressTime = now;
    const base = strengthLevels[Number(clickStrength?.value ?? 2)] ?? 1;
    return Math.min(2.1, base * (1 + clickSeries * 0.0875));
  }

  function burst(point, strength) {
    const type = activeCursor.effect || "spark";
    if (type === "comic") {
      clearEffects();
      for (let index = 0; index < 10; index += 1) {
        const angle = index * Math.PI / 5;
        const radius = 18 * strength;
        addEffect("comic", {
          x: point.x + Math.cos(angle) * radius,
          y: point.y + Math.sin(angle) * radius,
        }, {
          dx: Math.cos(angle) * 18 * strength,
          dy: Math.sin(angle) * 18 * strength,
          angle: index * 36,
          size: Math.max(2, 3 * strength),
          length: (index % 2 === 0 ? 12 : 8) * strength,
          color: "#fff",
          duration: 260,
        });
      }
      return;
    }
    if (reducedMotion.matches || type === "glow") {
      clearEffects();
      addEffect("glow", point, { size: 37 * strength, duration: 220 });
      return;
    }
    if (type === "laser") {
      const origin = { x: arena.clientWidth * 0.12, y: arena.clientHeight * 0.84 };
      const dx = point.x - origin.x;
      const dy = point.y - origin.y;
      addEffect("laser", origin, {
        angle: Math.atan2(dy, dx) * 180 / Math.PI,
        length: Math.hypot(dx, dy),
        size: 3 * strength,
        duration: 240,
      });
      addEffect("glow", point, { size: 29 * strength, duration: 330 });
      return;
    }

    const origin = type === "rainbow" ? rainbowOrigin(point) : point;
    const particleCount = type === "pounce" ? 4 : 6;
    const particleSize = type === "bongo" ? 20 : 8;
    for (let index = 0; index < particleCount; index += 1) {
      const radians = index * 2 * Math.PI / particleCount - Math.PI / 2;
      const distance = (index % 2 === 0 ? 31 : 47) * strength;
      addEffect(type, origin, {
        dx: Math.cos(radians) * distance,
        dy: Math.sin(radians) * distance,
        angle: index * 60,
        color: type === "rainbow" ? rainbow[index] : undefined,
        size: (index % 2 === 0 ? particleSize : particleSize - 3) * strength,
      });
    }
  }

  function playWave(file) {
    if (!wavePlayers.has(file)) {
      const player = new Audio(`assets/${file}.wav`);
      player.volume = 0.5;
      wavePlayers.set(file, player);
    }
    const player = wavePlayers.get(file);
    player.currentTime = 0;
    player.play().catch(() => {});
  }

  function press(point, fromTouch = false) {
    const cursor = activeCursor;
    const isBongo = cursor.effect === "bongo";
    const alternate = isBongo && nextBongoPaw === 1;
    const pressedFrame = (alternate && cursor.alternate) || cursor.pressed;
    if (pressedFrame) {
      pointerImage.src = pressedFrame;
      setRod(cursor.pressedRod || cursor.rod);
    }
    arena.classList.add("is-pressed");
    const strength = pressStrength();
    if (cursor.effect === "comic" && !reducedMotion.matches) {
      comicTap = { startedAt: performance.now(), strength };
      requestRodPose();
    }
    burst(point, strength);
    clearTimeout(pressTimer);
    pressTimer = window.setTimeout(() => {
      pointerImage.src = cursor.image;
      setRod(cursor.rod);
      arena.classList.remove("is-pressed");
    }, 210);

    if (soundEnabled) {
      const isMagic = ["rainbow", "laser", "spark", "glow"].includes(cursor.effect);
      const wave = isBongo ? (alternate ? "tap_bongo_right" : "tap_bongo_left") : (isMagic ? "tap_magic" : "tap_click");
      if (fromTouch) touchWave = wave;
      else playWave(wave);
    }
    if (isBongo) nextBongoPaw = 1 - nextBongoPaw;
  }

  function renderSoundState() {
    soundButtons.forEach((button) => {
      button.setAttribute("aria-pressed", String(soundEnabled));
      const label = button.querySelector("[data-sound-label]");
      if (label) label.textContent = soundEnabled ? "Звук включён" : "Звук выключен";
    });
  }

  filterButtons.forEach((button) => {
    button.addEventListener("click", () => {
      selectedFilter = button.dataset.filter;
      renderCatalog();
    });
  });
  search.addEventListener("input", renderCatalog);
  clickStrength?.addEventListener("change", resetClickSeries);
  demoButtons.forEach((button) => {
    const cursor = cursors.find(({ id }) => id === button.dataset.demoCursor);
    if (cursor) button.addEventListener("click", () => selectCursor(cursor));
  });
  if (cursorSize && cursorSizeValue) {
    const updateCursorSize = () => {
      const percent = cursorSize.valueAsNumber;
      pointer.style.setProperty("--cursor-scale", String(percent / 100));
      cursorSizeValue.textContent = `${percent}%`;
      cursorSize.setAttribute("aria-valuetext", `${percent} процентов`);
      requestRodPose();
    };
    cursorSize.addEventListener("input", updateCursorSize);
    updateCursorSize();
  }

  arena.addEventListener("pointerenter", (event) => {
    if (event.isPrimary) placePointer(event);
  });
  arena.addEventListener("pointermove", (event) => {
    if (event.isPrimary) addTrail(placePointer(event), event.timeStamp);
  });
  const releasePointer = () => {
    arena.classList.remove("is-pointer-active");
    lastTrail = null;
    nyanTurnX = null;
  };
  arena.addEventListener("pointerleave", releasePointer);
  arena.addEventListener("pointercancel", (event) => {
    releasePointer();
    if (event.isPrimary && event.pointerType === "touch") touchWave = null;
  });
  arena.addEventListener("pointerdown", (event) => {
    if (event.isPrimary && event.button === 0) press(placePointer(event), event.pointerType === "touch");
  });
  arena.addEventListener("pointerup", (event) => {
    if (!event.isPrimary || event.pointerType !== "touch") return;
    if (soundEnabled && touchWave) playWave(touchWave);
    touchWave = null;
  });
  arena.addEventListener("keydown", (event) => {
    if (event.target !== arena || (event.key !== "Enter" && event.key !== " ")) return;
    event.preventDefault();
    if (!event.repeat) press(centerPointer());
  });
  arena.addEventListener("click", (event) => {
    if (event.target === arena && event.detail === 0) press(centerPointer());
  });
  const handleMotionPreference = () => {
    resetClickSeries();
    resetComicTap();
    clearEffects();
    requestRodPose();
  };
  if (reducedMotion.addEventListener) reducedMotion.addEventListener("change", handleMotionPreference);
  else reducedMotion.addListener(handleMotionPreference);
  window.addEventListener("resize", requestRodPose);

  soundButtons.forEach((button) => {
    button.addEventListener("click", () => {
      soundEnabled = !soundEnabled;
      if (!soundEnabled) {
        touchWave = null;
        wavePlayers.forEach((player) => player.pause());
      }
      renderSoundState();
    });
  });
  selectCursor(cursors.find(({ id }) => id === arena.dataset.cursor)
    || cursors.find(({ effect }) => effect === "bongo") || cursors[0]);
  renderCatalog();
  renderSoundState();
})();
