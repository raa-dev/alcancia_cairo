// main.cairo
// Archivo ejecutable para pruebas locales

fn main() {
    // Imprime un mensaje simple en ASCII
    let message = 'Hello from StarknetJello';
    // Cairo no tiene println, pero podemos retornar el valor o usar syscalls en entornos compatibles
    // Aquí solo retornamos 0 para indicar éxito
    return ();
} 