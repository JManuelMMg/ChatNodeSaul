// Detectar si estamos en localhost o en producción
var isLocalhost = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
var socketUrl = isLocalhost ? 'http://localhost:4000' : window.location.origin;

var socket = io.connect(socketUrl);

var persona = document.getElementById('persona');
var appChat = document.getElementById('app-chat');
var panelBienvenida = document.getElementById('panel-bienvenida');
var usuario = document.getElementById('usuario');
var mensaje = document.getElementById('mensaje');
var botonEnviar = document.getElementById('boton-enviar');
var escribiendoMensaje = document.getElementById('escribiendo-mensaje');
var output = document.getElementById('output');

// Variables para configuración de notificaciones
var audioEnabled = document.getElementById('audio-enabled');
var volumeSlider = document.getElementById('volume-slider');
var volumeDisplay = document.getElementById('volume-display');
var soundType = document.getElementById('sound-type');
var visualNotifications = document.getElementById('visual-notifications');

// Configuración por defecto
var notificationConfig = {
  audioEnabled: true,
  volume: 0.4,
  soundType: 'normal',
  visualEnabled: true
};

botonEnviar.addEventListener('click', function(){
  if(mensaje.value){
    socket.emit('chat', {
      mensaje: mensaje.value,
      usuario: usuario.value
    });
    mensaje.value = '';
  }
});

mensaje.addEventListener('keyup', function(){
  if(persona.value){
    socket.emit('typing', {
      nombre: usuario.value,
      texto: mensaje.value
    });
  }
});

socket.on('chat', function(data){
  escribiendoMensaje.innerHTML = '';
  output.innerHTML += '<p><strong>' + data.usuario + ': </strong>' + data.mensaje + '</p>';
  
  // Reproducir sonido de notificación según configuración
  if (notificationConfig.audioEnabled) {
  playNotificationSound();
  }
  
  // Mostrar notificación visual si está habilitada
  if (notificationConfig.visualEnabled) {
    showMessageNotification(data.usuario);
  }
});

socket.on('typing', function(data) {
  if(data.texto){
    escribiendoMensaje.innerHTML = '<p><em>' + data.nombre + ' esta escribiendo un mensaje...</em></p>';
  } else {
    escribiendoMensaje.innerHTML = '';
  }
});

function ingresarAlChat(){
  if(persona.value){
    panelBienvenida.style.display = "none";
    appChat.style.display = "block";
    var nombreDeUsuario = persona.value;
    usuario.value = nombreDeUsuario;
    usuario.readOnly = true;
  }
}

// Función para reproducir sonido de notificación mejorado
function playNotificationSound() {
  try {
    // Determinar qué tipo de sonido reproducir
    switch (notificationConfig.soundType) {
      case 'special':
        playSpecialNotification();
        break;
      case 'simple':
        playSimpleNotification();
        break;
      default:
        playNormalNotification();
        break;
    }
  } catch (error) {
    console.log('Error reproduciendo notificación de audio:', error);
    playSimpleNotification();
  }
}

// Función para notificación normal mejorada
function playNormalNotification() {
  try {
    var audioContext = new (window.AudioContext || window.webkitAudioContext)();
    
    // Crear múltiples osciladores para un sonido más rico
    var oscillator1 = audioContext.createOscillator();
    var oscillator2 = audioContext.createOscillator();
    var gainNode = audioContext.createGain();
    var filterNode = audioContext.createBiquadFilter();
    
    // Conectar los nodos
    oscillator1.connect(filterNode);
    oscillator2.connect(filterNode);
    filterNode.connect(gainNode);
    gainNode.connect(audioContext.destination);
    
    // Configurar filtro para un sonido más suave
    filterNode.type = 'lowpass';
    filterNode.frequency.setValueAtTime(1000, audioContext.currentTime);
    
    // Configurar osciladores con diferentes frecuencias
    oscillator1.type = 'sine';
    oscillator1.frequency.setValueAtTime(800, audioContext.currentTime);
    oscillator1.frequency.setValueAtTime(600, audioContext.currentTime + 0.15);
    
    oscillator2.type = 'sine';
    oscillator2.frequency.setValueAtTime(1200, audioContext.currentTime);
    oscillator2.frequency.setValueAtTime(900, audioContext.currentTime + 0.15);
    
    // Configurar volumen según configuración del usuario
    var volume = notificationConfig.volume;
    gainNode.gain.setValueAtTime(volume, audioContext.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.3);
    
    // Reproducir el sonido
    oscillator1.start(audioContext.currentTime);
    oscillator2.start(audioContext.currentTime);
    oscillator1.stop(audioContext.currentTime + 0.3);
    oscillator2.stop(audioContext.currentTime + 0.3);
    
  } catch (error) {
    console.log('Error en notificación normal:', error);
    playSimpleNotification();
  }
}

// Función de respaldo para notificación simple
function playSimpleNotification() {
  try {
  var audioContext = new (window.AudioContext || window.webkitAudioContext)();
  var oscillator = audioContext.createOscillator();
  var gainNode = audioContext.createGain();
  
  oscillator.connect(gainNode);
  gainNode.connect(audioContext.destination);
  
  oscillator.frequency.setValueAtTime(800, audioContext.currentTime);
  oscillator.frequency.setValueAtTime(600, audioContext.currentTime + 0.1);
  
  gainNode.gain.setValueAtTime(0.3, audioContext.currentTime);
  gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.2);
  
  oscillator.start(audioContext.currentTime);
  oscillator.stop(audioContext.currentTime + 0.2);
  } catch (error) {
    console.log('No se pudo reproducir notificación de audio');
  }
}

// Función para mostrar notificación visual
function showMessageNotification(usuario) {
  // Crear elemento de notificación temporal
  var notification = document.createElement('div');
  notification.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    background: #4CAF50;
    color: white;
    padding: 15px 20px;
    border-radius: 5px;
    box-shadow: 0 4px 8px rgba(0,0,0,0.3);
    z-index: 1000;
    font-family: Arial, sans-serif;
    font-size: 14px;
    animation: slideIn 0.3s ease-out;
  `;
  notification.innerHTML = '💬 Nuevo mensaje de: <strong>' + usuario + '</strong>';
  
  // Añadir estilos de animación
  var style = document.createElement('style');
  style.textContent = `
    @keyframes slideIn {
      from { transform: translateX(100%); opacity: 0; }
      to { transform: translateX(0); opacity: 1; }
    }
    @keyframes slideOut {
      from { transform: translateX(0); opacity: 1; }
      to { transform: translateX(100%); opacity: 0; }
    }
  `;
  document.head.appendChild(style);
  
  document.body.appendChild(notification);
  
  // Remover la notificación después de 3 segundos
  setTimeout(function() {
    notification.style.animation = 'slideOut 0.3s ease-in';
    setTimeout(function() {
      if (notification.parentNode) {
        notification.parentNode.removeChild(notification);
      }
    }, 300);
  }, 3000);
}

// Función para reproducir sonido de notificación especial
function playSpecialNotification() {
  try {
    var audioContext = new (window.AudioContext || window.webkitAudioContext)();
    
    // Crear secuencia de sonidos más elaborada
    var oscillator1 = audioContext.createOscillator();
    var oscillator2 = audioContext.createOscillator();
    var oscillator3 = audioContext.createOscillator();
    var gainNode = audioContext.createGain();
    
    oscillator1.connect(gainNode);
    oscillator2.connect(gainNode);
    oscillator3.connect(gainNode);
    gainNode.connect(audioContext.destination);
    
    // Configurar diferentes tipos de onda
    oscillator1.type = 'sine';
    oscillator2.type = 'triangle';
    oscillator3.type = 'sawtooth';
    
    // Secuencia de frecuencias para un sonido más musical
    oscillator1.frequency.setValueAtTime(523, audioContext.currentTime); // C5
    oscillator2.frequency.setValueAtTime(659, audioContext.currentTime); // E5
    oscillator3.frequency.setValueAtTime(784, audioContext.currentTime); // G5
    
    oscillator1.frequency.setValueAtTime(659, audioContext.currentTime + 0.1); // E5
    oscillator2.frequency.setValueAtTime(784, audioContext.currentTime + 0.1); // G5
    oscillator3.frequency.setValueAtTime(1047, audioContext.currentTime + 0.1); // C6
    
    gainNode.gain.setValueAtTime(0.2, audioContext.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.4);
    
    oscillator1.start(audioContext.currentTime);
    oscillator2.start(audioContext.currentTime);
    oscillator3.start(audioContext.currentTime);
    
    oscillator1.stop(audioContext.currentTime + 0.4);
    oscillator2.stop(audioContext.currentTime + 0.4);
    oscillator3.stop(audioContext.currentTime + 0.4);
    
  } catch (error) {
    console.log('Error en notificación especial:', error);
    playSimpleNotification();
  }
}

// Event listeners para configuración de notificaciones
document.addEventListener('DOMContentLoaded', function() {
  // Configurar controles de audio
  if (audioEnabled) {
    audioEnabled.addEventListener('change', function() {
      notificationConfig.audioEnabled = this.checked;
    });
  }
  
  if (volumeSlider && volumeDisplay) {
    volumeSlider.addEventListener('input', function() {
      var volume = this.value / 100;
      notificationConfig.volume = volume;
      volumeDisplay.textContent = this.value + '%';
    });
  }
  
  if (soundType) {
    soundType.addEventListener('change', function() {
      notificationConfig.soundType = this.value;
    });
  }
  
  if (visualNotifications) {
    visualNotifications.addEventListener('change', function() {
      notificationConfig.visualEnabled = this.checked;
    });
  }
});
