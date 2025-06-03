#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/gpio.h>
#include <linux/interrupt.h>
#include <linux/delay.h>
#include <linux/workqueue.h>

#define DRIVER_NAME "gpio_button_led"
#define BUTTON_GPIO 44    /* P8_12 = GPIO1_12 = 32*1 + 12 = 44 */
#define LED_GPIO    61    /* P8_26 = GPIO1_29 = 32*1 + 29 = 61 */

static unsigned int irq_number;
static bool led_state = false;
static struct workqueue_struct *button_wq;

/* Work structure for button debouncing */
struct button_work {
    struct work_struct work;
    unsigned long timestamp;
};

static struct button_work button_work_struct;

/* Work function to handle button press with debouncing */
static void button_work_handler(struct work_struct *work)
{
    static unsigned long last_interrupt_time = 0;
    unsigned long interrupt_time = jiffies;

    /* Simple debouncing - ignore interrupts within 200ms */
    if (interrupt_time - last_interrupt_time < msecs_to_jiffies(200)) {
        return;
    }
    last_interrupt_time = interrupt_time;

    /* Read button state (active low due to pullup) */
    if (gpio_get_value(BUTTON_GPIO) == 0) {
        /* Button pressed - toggle LED */
        led_state = !led_state;
        gpio_set_value(LED_GPIO, led_state);

        printk(KERN_INFO "%s: Button pressed, LED %s\n",
               DRIVER_NAME, led_state ? "ON" : "OFF");
    }
}

/* Interrupt handler for button press */
static irqreturn_t button_irq_handler(int irq, void *dev_id)
{
    /* Schedule work to handle button press (avoids doing work in IRQ context) */
    queue_work(button_wq, &button_work_struct.work);
    return IRQ_HANDLED;
}

/* Driver initialization */
static int __init gpio_button_led_init(void)
{
    int result = 0;

    printk(KERN_INFO "%s: Initializing GPIO Button LED driver\n", DRIVER_NAME);

    /* Request GPIO for button (input) */
    if (!gpio_is_valid(BUTTON_GPIO)) {
        printk(KERN_ERR "%s: Invalid button GPIO %d\n", DRIVER_NAME, BUTTON_GPIO);
        return -ENODEV;
    }

    result = gpio_request(BUTTON_GPIO, "button_gpio");
    if (result < 0) {
        printk(KERN_ERR "%s: Failed to request button GPIO %d\n", DRIVER_NAME, BUTTON_GPIO);
        return result;
    }

    /* Set button GPIO as input */
    result = gpio_direction_input(BUTTON_GPIO);
    if (result < 0) {
        printk(KERN_ERR "%s: Failed to set button GPIO direction\n", DRIVER_NAME);
        goto fail_button_direction;
    }

    /* Request GPIO for LED (output) */
    if (!gpio_is_valid(LED_GPIO)) {
        printk(KERN_ERR "%s: Invalid LED GPIO %d\n", DRIVER_NAME, LED_GPIO);
        result = -ENODEV;
        goto fail_button_direction;
    }

    result = gpio_request(LED_GPIO, "led_gpio");
    if (result < 0) {
        printk(KERN_ERR "%s: Failed to request LED GPIO %d\n", DRIVER_NAME, LED_GPIO);
        goto fail_button_direction;
    }

    /* Set LED GPIO as output and initially OFF */
    result = gpio_direction_output(LED_GPIO, 0);
    if (result < 0) {
        printk(KERN_ERR "%s: Failed to set LED GPIO direction\n", DRIVER_NAME);
        goto fail_led_direction;
    }

    /* Create workqueue for button handling */
    button_wq = create_singlethread_workqueue("button_wq");
    if (!button_wq) {
        printk(KERN_ERR "%s: Failed to create workqueue\n", DRIVER_NAME);
        result = -ENOMEM;
        goto fail_led_direction;
    }

    /* Initialize work structure */
    INIT_WORK(&button_work_struct.work, button_work_handler);

    /* Get IRQ number for button GPIO */
    irq_number = gpio_to_irq(BUTTON_GPIO);
    if (irq_number < 0) {
        printk(KERN_ERR "%s: Failed to get IRQ for button GPIO\n", DRIVER_NAME);
        result = irq_number;
        goto fail_workqueue;
    }

    /* Request interrupt for button press (falling edge - button press) */
    result = request_irq(irq_number,
                        button_irq_handler,
                        IRQF_TRIGGER_FALLING,
                        "button_irq",
                        NULL);
    if (result < 0) {
        printk(KERN_ERR "%s: Failed to request IRQ %d\n", DRIVER_NAME, irq_number);
        goto fail_workqueue;
    }

    printk(KERN_INFO "%s: Driver loaded successfully\n", DRIVER_NAME);
    printk(KERN_INFO "%s: Button GPIO: %d, LED GPIO: %d, IRQ: %d\n",
           DRIVER_NAME, BUTTON_GPIO, LED_GPIO, irq_number);

    return 0;

fail_workqueue:
    destroy_workqueue(button_wq);
fail_led_direction:
    gpio_free(LED_GPIO);
fail_button_direction:
    gpio_free(BUTTON_GPIO);
    return result;
}

/* Driver cleanup */
static void __exit gpio_button_led_exit(void)
{
    printk(KERN_INFO "%s: Cleaning up GPIO Button LED driver\n", DRIVER_NAME);

    /* Free interrupt */
    free_irq(irq_number, NULL);

    /* Destroy workqueue */
    destroy_workqueue(button_wq);

    /* Turn off LED and free GPIOs */
    gpio_set_value(LED_GPIO, 0);
    gpio_free(LED_GPIO);
    gpio_free(BUTTON_GPIO);

    printk(KERN_INFO "%s: Driver unloaded\n", DRIVER_NAME);
}

module_init(gpio_button_led_init);
module_exit(gpio_button_led_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("BeagleBone GPIO Driver");
MODULE_DESCRIPTION("Button press controls LED - P8_12 button, P8_26 LED");
MODULE_VERSION("1.0");
